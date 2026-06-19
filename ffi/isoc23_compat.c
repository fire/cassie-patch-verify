/* Stubs for glibc 2.38+ __isoc23_* aliases.
 * NO #include headers — the __asm__-based rename in glibc's stdlib.h/stdio.h
 * is what causes __isoc23_strtoll to appear in compiled code. Without headers,
 * we call the classic names directly and they stay as strtoll/sscanf in the object.
 */

/* Provide our own prototypes without triggering glibc's __asm__ aliases */
long long strtoll(const char *, char **, int);
unsigned long long strtoull(const char *, char **, int);
long strtol(const char *, char **, int);
unsigned long strtoul(const char *, char **, int);

/* Forward-declare vsscanf without va_list (use void*; ABI-compatible on x86-64) */
int vsscanf(const char *, const char *, void *);

/* We cannot use va_list without <stdarg.h>, but on x86-64 SystemV ABI,
 * passing ... to a function that expects va_list works because the caller
 * saves the register args. Use __builtin_va_list (compiler built-in, no header). */

long long __isoc23_strtoll(const char *s, char **e, int b) {
    return strtoll(s, e, b);
}
unsigned long long __isoc23_strtoull(const char *s, char **e, int b) {
    return strtoull(s, e, b);
}
long __isoc23_strtol(const char *s, char **e, int b) {
    return strtol(s, e, b);
}
unsigned long __isoc23_strtoul(const char *s, char **e, int b) {
    return strtoul(s, e, b);
}

int __isoc23_sscanf(const char *str, const char *fmt, ...) {
    __builtin_va_list ap;
    __builtin_va_start(ap, fmt);
    int r = vsscanf(str, fmt, ap);
    __builtin_va_end(ap);
    return r;
}
