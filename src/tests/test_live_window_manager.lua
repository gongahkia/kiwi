local Manager = require("kiwi.app.window_manager")

return {
  live_window_manager_keeps_new_windows_in_one_application_scheduler = function()
    local waits = 0
    local polls = 0
    local created = 0
    local controller_options = {}
    local manager = Manager.new(function(options)
      created = created + 1
      controller_options[created] = options
      local window = { id = created }
      if created == 1 then
        assert(options.application:request_window(nil, {
          kind = "host-tab",
          source_controller_id = options.controller_id,
        }))
      end
      options.application:await_events(window, 0.001)
    end, { menu_smoke = true, multi_window_smoke = true }, {
      window_api = {
        poll_events_for = function(windows)
          polls = polls + 1
          assert(#windows >= 1)
        end,
        wait_events_for = function(timeout, windows)
          waits = waits + 1
          assert(timeout >= 0)
          assert(#windows >= 1)
        end,
      },
    })
    manager:run()
    assert(created == 2, "new window did not receive a manager-owned controller")
    assert(controller_options[1].multi_window_smoke_requester == true, "the initial controller should own the smoke request")
    assert(controller_options[2].multi_window_smoke_requester == false, "new controllers must not recursively request windows")
    assert(controller_options[2].menu_smoke == false, "new controllers must not repeat one-shot smoke actions")
    assert(controller_options[2].host_tab == true, "native-tab requests must retain their explicit host intent")
    assert(controller_options[2].host_tab_source_id == controller_options[1].controller_id, "native-tab requests must retain their source controller")
    assert(waits == 2 and polls == 2, "each controller turn should share one platform event wait and poll")
    assert(manager:window_count() == 0, "ended controllers must leave the manager")
  end,

  live_window_manager_rejects_recording_and_window_limit_requests = function()
    local recorder_manager = Manager.new(function() end, { record = "recording.jsonl" })
    local opened, reason = recorder_manager:request_window()
    assert(opened == nil and reason == "new windows are unavailable while --record is active")

    local limited_manager = Manager.new(function(options)
      options.application:await_events({}, 0)
    end, { maximum_windows = 1 }, {
      window_api = { poll_events_for = function() end, wait_events_for = function() end },
    })
    assert(limited_manager:request_window())
    local limited, limited_reason = limited_manager:request_window()
    assert(limited == nil and limited_reason == "window-limit")
  end,

  live_window_manager_marks_explicit_new_windows_as_separate_native_windows = function()
    local manager = Manager.new(function() end, {})
    assert(manager:request_window(nil, { initial_cwd = "/tmp/kiwi work", kind = "standalone" }))
    assert(manager.controllers[1].options.host_tab == false)
    assert(manager.controllers[1].options.host_tab_source_id == nil)
    assert(manager.controllers[1].options.initial_cwd == "/tmp/kiwi work")
    local opened, reason = manager:request_window(nil, { initial_cwd = "relative", kind = "standalone" })
    assert(opened == nil and reason == "invalid-working-directory")
  end,
  live_window_manager_validates_host_tab_source_identity = function()
    local manager = Manager.new(function() end, {})
    local opened, reason = manager:request_window(nil, true)
    assert(opened == nil and reason == "invalid-window-request")
    opened, reason = manager:request_window(nil, { kind = "host-tab", source_controller_id = 1 })
    assert(opened == nil and reason == "unknown-source-window")
    local source = assert(manager:_start({}))
    assert(manager:request_window(nil, { kind = "host-tab", source_controller_id = source.id }))
    assert(manager.controllers[2].options.host_tab == true)
    assert(manager.controllers[2].options.host_tab_source_id == source.id)
  end,

  live_window_manager_transfers_live_sessions_transactionally_and_persists_topology = function()
    local persisted
    local manager = Manager.new(function() end, { layout_persistence = true, layout_restore = false }, {
      layout_path = "memory://layout",
      layout_store = { write = function(_, snapshot) persisted = snapshot; return true end },
    })
    local source = assert(manager:_start({}))
    local destination = assert(manager:_start({}))
    local transferred = { id = "running-pty" }
    local created = 0
    local source_active = transferred
    local destination_sessions = {}
    local function snapshot(id, panes)
      return {
        geometry = { height = 800, width = 1200, x = id * 10, y = id * 20 },
        workspace = {
          active_tab_id = 1,
          tabs = { { active_pane_id = 1, id = 1, pane_count = panes, root = { kind = "leaf", pane_id = 1 } } },
        },
      }
    end
    assert(manager:register_controller(source.id, {
      begin_transfer = function()
        local session = source_active
        source_active = nil
        return session
      end,
      complete_transfer = function(session)
        assert(session == transferred)
        return true
      end,
      destroy_session = function() error("unexpected duplicate cleanup") end,
      new_session = function() created = created + 1; return { id = "fresh-" .. created } end,
      restore_transfer = function(session) source_active = session; return true end,
      snapshot = function() return snapshot(source.id, 1) end,
    }))
    assert(manager:register_controller(destination.id, {
      accept_transfer = function(session) destination_sessions[#destination_sessions + 1] = session; return true end,
      snapshot = function() return snapshot(destination.id, #destination_sessions + 1) end,
    }))
    assert(manager:move_active_to_next_window(source.id))
    assert(destination_sessions[1] == transferred)
    assert(source_active == nil)
    assert(manager:duplicate_active_to_next_window(source.id))
    assert(destination_sessions[2].id == "fresh-1")
    assert(manager:_write_layout())
    assert(persisted.schema_version == 2 and #persisted.windows == 2 and persisted.windows[1].id == nil)

    local rollback = Manager.new(function() end, {}, { window_api = { poll_events_for = function() end, wait_events_for = function() end } })
    local rollback_source = assert(rollback:_start({}))
    local recovered = { id = "must-return" }
    local pending = recovered
    assert(rollback:register_controller(rollback_source.id, {
      begin_transfer = function() local session = pending; pending = nil; return session end,
      complete_transfer = function() return true end,
      destroy_session = function() end,
      new_session = function() return {} end,
      restore_transfer = function(session) pending = session; return true end,
      snapshot = function() return snapshot(rollback_source.id, pending and 1 or 0) end,
    }))
    assert(rollback:move_active_to_new_window(rollback_source.id))
    rollback:_remove(2)
    assert(pending == recovered)
  end,

  live_window_manager_selects_a_live_destination_and_rolls_back_exactly_once = function()
    local manager = Manager.new(function() end, {})
    local source = assert(manager:_start({}))
    local first = assert(manager:_start({}))
    local second = assert(manager:_start({}))
    local source_session = { id = "live-pty" }
    local active = source_session
    local restored = 0
    local first_received = 0
    local second_received = 0
    local function snapshot()
      return {
        geometry = { height = 800, width = 1200, x = 0, y = 0 },
        workspace = { active_tab_id = 1, tabs = { { active_pane_id = 1, id = 1, root = { kind = "leaf", pane_id = 1 } } } },
      }
    end
    assert(manager:register_controller(source.id, {
      begin_transfer = function() local session = active; active = nil; return session end,
      complete_transfer = function(session) assert(session == source_session); return true end,
      destroy_session = function() error("live transfer must not destroy the source session") end,
      new_session = function() return { id = "fresh" } end,
      restore_transfer = function(session) restored = restored + 1; active = session; return true end,
      snapshot = snapshot,
    }))
    assert(manager:register_controller(first.id, {
      accept_transfer = function() first_received = first_received + 1; return true end,
      snapshot = snapshot,
    }))
    assert(manager:register_controller(second.id, {
      accept_transfer = function(session) second_received = second_received + 1; assert(session == source_session); return true end,
      snapshot = snapshot,
    }))
    local targets = assert(manager:session_targets(source.id))
    assert(#targets == 2 and targets[1].id == first.id and targets[2].id == second.id)
    assert(manager:move_active_to_window(source.id, second.id))
    assert(first_received == 0 and second_received == 1 and active == nil and restored == 0)

    local rollback = Manager.new(function() end, {})
    local rollback_source = assert(rollback:_start({}))
    local rollback_target = assert(rollback:_start({}))
    local pending = { id = "must-return" }
    local restore_count = 0
    local destroy_count = 0
    assert(rollback:register_controller(rollback_source.id, {
      begin_transfer = function() local session = pending; pending = nil; return session end,
      complete_transfer = function() error("rejected transfer must not complete") end,
      destroy_session = function(session) destroy_count = destroy_count + 1; assert(session.id == "fresh") end,
      new_session = function() return { id = "fresh" } end,
      restore_transfer = function(session) restore_count = restore_count + 1; pending = session; return true end,
      snapshot = snapshot,
    }))
    assert(rollback:register_controller(rollback_target.id, {
      accept_transfer = function() return nil, "tab-limit" end,
      snapshot = snapshot,
    }))
    local moved, move_reason = rollback:move_active_to_window(rollback_source.id, rollback_target.id)
    assert(moved == nil and move_reason == "tab-limit" and pending.id == "must-return" and restore_count == 1)
    local duplicated, duplicate_reason = rollback:duplicate_active_to_window(rollback_source.id, rollback_target.id)
    assert(duplicated == nil and duplicate_reason == "tab-limit" and destroy_count == 1 and restore_count == 1)
    local same, same_reason = rollback:move_active_to_window(rollback_source.id, rollback_source.id)
    assert(same == nil and same_reason == "same-window-target" and restore_count == 1)
  end,

  live_window_manager_promotes_a_default_legacy_layout_without_reading_past_a_future_file = function()
    local reads = {}
    local migrated = {
      schema_version = 2,
      windows = {
        { geometry = { height = 800, width = 1200, x = 0, y = 0 }, workspace = {
          active_tab_id = 1,
          tabs = { { active_pane_id = 1, id = 1, root = { kind = "leaf", pane_id = 1 } } },
        } },
      },
    }
    local manager = Manager.new(function() end, {}, {
      layout_path = "memory://workspace-v2",
      legacy_layout_path = "memory://workspace-v1",
      layout_store = {
        load = function(path)
          reads[#reads + 1] = path
          if path == "memory://workspace-v2" then return nil, "missing" end
          return migrated
        end,
      },
    })
    assert(manager:_read_layout() == migrated)
    assert(manager.layout_dirty and reads[1] == "memory://workspace-v2" and reads[2] == "memory://workspace-v1")

    reads = {}
    manager = Manager.new(function() end, {}, {
      layout_path = "memory://workspace-v2",
      legacy_layout_path = "memory://workspace-v1",
      layout_store = { load = function(path) reads[#reads + 1] = path; return nil, "unsupported-layout-version" end },
    })
    assert(manager:_read_layout() == nil)
    assert(#reads == 1 and reads[1] == "memory://workspace-v2")
  end,

  live_window_manager_rehydrates_persisted_windows_with_fresh_workspace_descriptors = function()
    local started = {}
    local writes = 0
    local stored = {
      schema_version = 1,
      windows = {
        { id = 9, geometry = { height = 800, width = 1200, x = 30, y = 40 }, workspace = {
          active_tab_id = 4,
          tabs = { { active_pane_id = 5, id = 4, pane_count = 1, root = { kind = "leaf", pane_id = 5 } } },
        } },
      },
    }
    local manager = Manager.new(function(options)
      started[#started + 1] = options
      assert(options.layout_restored and options.command == nil)
      assert(options.restored_workspace.tabs[1].root.session == nil)
      assert(options.application:register_controller(options.controller_id, {
        snapshot = function()
          return { geometry = options.geometry, workspace = options.restored_workspace }
        end,
      }))
      options.application:await_events({ id = options.controller_id }, 0)
      assert(options.application:unregister_controller(options.controller_id))
    end, {}, {
      layout_path = "memory://layout",
      layout_store = {
        load = function() return stored end,
        write = function() writes = writes + 1; return true end,
      },
      window_api = { poll_events_for = function() end, wait_events_for = function() end },
    })
    manager:run()
    assert(#started == 1 and started[1].geometry.x == 30 and writes == 1)
  end,
}
