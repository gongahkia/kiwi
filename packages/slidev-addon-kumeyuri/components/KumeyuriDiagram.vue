<template>
  <figure class="kumeyuri-diagram" :data-loading="loading || undefined" :data-error="error || undefined">
    <pre class="kumeyuri-diagram-frame" aria-live="polite">{{ currentText }}</pre>
    <figcaption v-if="caption" class="kumeyuri-diagram-caption">{{ caption }}</figcaption>
    <div v-if="controls" class="kumeyuri-diagram-controls">
      <button type="button" @click="toggle">{{ playing ? "Pause" : "Play" }}</button>
      <button type="button" @click="restart">Restart</button>
      <input v-model.number="index" type="range" min="0" :max="maxFrame" step="1" aria-label="Frame" @input="pause">
    </div>
  </figure>
</template>

<script setup>
import { computed, onBeforeUnmount, onMounted, ref, watch } from "vue";

const props = defineProps({
  src: { type: String, required: true },
  caption: { type: String, default: "" },
  autoplay: { type: Boolean, default: false },
  controls: { type: Boolean, default: true },
  loop: { type: Boolean, default: false },
});

const cast = ref(null);
const error = ref("");
const index = ref(0);
const loading = ref(false);
const playing = ref(false);
let timer = 0;

const frames = computed(() => cast.value?.timeline?.frames ?? []);
const maxFrame = computed(() => Math.max(0, frames.value.length - 1));
const currentText = computed(() => {
  if (error.value) return error.value;
  if (loading.value) return "Loading kumecast...";
  const frame = frames.value[index.value];
  return frame ? frameText(frame) : "";
});

onMounted(load);
onBeforeUnmount(stop);
watch(() => props.src, load);
watch(index, () => {
  if (index.value > maxFrame.value) index.value = maxFrame.value;
});

async function load() {
  stop();
  loading.value = true;
  error.value = "";
  index.value = 0;
  try {
    const response = await fetch(props.src, { headers: { Accept: "application/json, */*;q=0.1" } });
    if (!response.ok) throw new Error(`failed to fetch cast: ${response.status}`);
    cast.value = validateCast(await response.json());
    if (props.autoplay) play();
  } catch (cause) {
    cast.value = null;
    error.value = cause instanceof Error ? cause.message : String(cause);
  } finally {
    loading.value = false;
  }
}

function validateCast(value) {
  if (!value || typeof value !== "object") throw new Error("cast must be an object");
  if (value.version !== 1) throw new Error(`unsupported cast version ${JSON.stringify(value.version)}`);
  if (!Array.isArray(value.timeline?.frames) || value.timeline.frames.length === 0) {
    throw new Error("cast timeline.frames must be non-empty");
  }
  for (const [frameIndex, frame] of value.timeline.frames.entries()) {
    if (!Number.isInteger(frame.width) || !Number.isInteger(frame.height)) {
      throw new Error(`frame ${frameIndex} has invalid dimensions`);
    }
    if (!Array.isArray(frame.cells) || frame.cells.length !== frame.width * frame.height) {
      throw new Error(`frame ${frameIndex} cell count does not match dimensions`);
    }
    if (!Number.isFinite(frame.durationMs)) {
      throw new Error(`frame ${frameIndex} durationMs is invalid`);
    }
  }
  return value;
}

function frameText(frame) {
  const rows = [];
  for (let y = 0; y < frame.height; y += 1) {
    let row = "";
    for (let x = 0; x < frame.width; x += 1) {
      row += frame.cells[y * frame.width + x].glyph;
    }
    rows.push(row.replace(/\s+$/u, ""));
  }
  return rows.join("\n").replace(/\n+$/u, "");
}

function toggle() {
  playing.value ? pause() : play();
}

function play() {
  if (frames.value.length < 2) return;
  playing.value = true;
  schedule();
}

function pause() {
  playing.value = false;
  clearTimeout(timer);
}

function restart() {
  index.value = 0;
  play();
}

function stop() {
  pause();
  cast.value = null;
}

function schedule() {
  clearTimeout(timer);
  if (!playing.value) return;
  const frame = frames.value[index.value];
  timer = setTimeout(() => {
    const next = index.value + 1;
    if (next >= frames.value.length && !(props.loop || cast.value?.timeline?.repeat)) {
      pause();
      return;
    }
    index.value = next % frames.value.length;
    schedule();
  }, Math.max(1, frame?.durationMs ?? 1));
}
</script>

<style scoped>
.kumeyuri-diagram {
  display: grid;
  gap: 0.4rem;
  margin: 0;
}

.kumeyuri-diagram-frame {
  font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
  font-size: 0.72em;
  line-height: 1.15;
  margin: 0;
  overflow: auto;
  white-space: pre;
}

.kumeyuri-diagram-controls {
  align-items: center;
  display: flex;
  gap: 0.4rem;
}
</style>
