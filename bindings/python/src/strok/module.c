#define PY_SSIZE_T_CLEAN
#include <Python.h>

#include <strok/c_api.h>

static PyObject* strok_abi_version(PyObject* self, PyObject* arguments) {
  (void)self;
  if (!PyArg_ParseTuple(arguments, "")) {
    return NULL;
  }
  return PyLong_FromUnsignedLong(STROK_C_ABI_VERSION);
}

static PyMethodDef strok_methods[] = {
    {
        "abi_version",
        strok_abi_version,
        METH_VARARGS,
        "Return the C ABI version linked by this extension.",
    },
    {NULL, NULL, 0, NULL},
};

static struct PyModuleDef strok_module = {
    PyModuleDef_HEAD_INIT,
    "_strok",
    "Native C ABI smoke binding for strok.",
    -1,
    strok_methods,
};

PyMODINIT_FUNC PyInit__strok(void) {
  StrokRendererConfig config;
  strok_renderer_config_init(&config);
  if (config.version != STROK_C_ABI_VERSION || config.struct_size != sizeof(config)) {
    PyErr_Format(
        PyExc_ImportError,
        "strok C ABI mismatch: expected version %u and config size %zu, got version %u and config size %u",
        STROK_C_ABI_VERSION,
        sizeof(config),
        config.version,
        config.struct_size);
    return NULL;
  }
  return PyModule_Create(&strok_module);
}
