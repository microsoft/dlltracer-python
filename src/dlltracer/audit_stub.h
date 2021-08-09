
#ifdef __cplusplus
extern "C" {
#endif

#if PY_VERSION_HEX < 0x03080000
int __stdcall PySys_Audit(const char* event, const char* fmt, ...);
#endif

#ifdef __cplusplus
}
#endif
