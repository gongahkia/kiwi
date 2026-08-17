local GtkWindow = require("kiwi.platform.gtk_window")

assert(GtkWindow.bridge ~= nil, "GTK host bridge was not loaded")
assert(type(GtkWindow.bridge.kiwi_gtk_host_new) == "cdata", "GTK host constructor ABI is unavailable")
assert(type(GtkWindow.bridge.kiwi_gtk_host_create_surface) == "cdata", "GTK host surface ABI is unavailable")
print("GTK host ABI check passed.")
