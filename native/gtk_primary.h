#ifndef KIWI_GTK_PRIMARY_H
#define KIWI_GTK_PRIMARY_H
#include <gdk/gdk.h>
#include "primary_selection.h"

typedef struct KiwiGtkPrimaryRead KiwiGtkPrimaryRead;
/* Main-context thread only. Requests retain their own callback lifetime. */
KiwiGtkPrimaryRead *kiwi_gtk_primary_read_new(GdkClipboard *clipboard, size_t maximum_bytes, unsigned timeout_ms);
int kiwi_gtk_primary_read_poll(KiwiGtkPrimaryRead *read);
const char *kiwi_gtk_primary_read_text(const KiwiGtkPrimaryRead *read, size_t *bytes);
void kiwi_gtk_primary_read_destroy(KiwiGtkPrimaryRead *read);
#endif
