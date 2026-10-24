// SPDX-License-Identifier: MIT
// See FORK-LICENSE.md for what that identifier covers.
//
//! Generates the runtime-loaded `c` module from the selected translation; do not link the native archive.
//! FreeType and `libc_noise` declarations stay linked; HarfBuzz symbols use the provider.

const std = @import("std");

/// The prefix compiled into `runtime/sync.c`; it must match `runtime/library.zig`.
/// Use a different prefix in both files for independent SDK instances.
const sync_prefix = "harfbuzz_rt";

/// Comma-separated libc declarations kept out of provider routing.
/// End every name with a comma; the generator splits and trims the list.
const libc_noise =
    \\\, _CountofType, _Exit, _MarkAllocaS, _OSSwapInt16, _OSSwapInt32, _OSSwapInt64,
    \\__DARWIN_OSSwapConstInt16, __DARWIN_OSSwapConstInt32, __DARWIN_OSSwapConstInt64, ___mb_cur_max,
    \\___mb_cur_max_func, ___mb_cur_max_l, __acrt_iob_func, __aligned, __aligned__, __alignof__,
    \\__alloc_align, __alloc_size, __alloc_size2, __asprintf, __asprintf_chk, __attr_access,
    \\__attr_dealloc, __attr_dealloc_fclose, __attr_dealloc_free, __bcopy_ptrcheck, __bos, __bounded__,
    \\__bswap_16, __bswap_32, __bswap_64, __bswap_constant_16, __bswap_constant_32, __bswap_constant_64,
    \\__bzero_ptrcheck, __call, __ceilf16, __chk_fail, __copysignf16, __cospi, __cospif,
    \\__countof_helper, __ctype_get_mb_cur_max, __daylight, __dead2, __debugbreak, __doserrno,
    \\__dprintf_chk, __dstbias, __errno, __errno_location, __exp10, __exp10f, __explicit_bzero_chk,
    \\__fabsf16, __fastfail, __fdelt_chk, __fdelt_warn, __feof_unlocked_body, __ferror_unlocked_body,
    \\__fgets_alias, __fgets_chk, __fgets_chk_warn, __fgets_unlocked_alias, __fgets_unlocked_chk,
    \\__fgets_unlocked_chk_warn, __floorf16, __fmaf16, __fmaxf16, __fminf16, __fortified_attr_access,
    \\__fp_unordered_compare, __fpclassify, __fpclassifyd, __fpclassifyd128, __fpclassifyd32,
    \\__fpclassifyd64, __fpclassifyf, __fpclassifyf128, __fpclassifyl, __fprintf_chk, __fread_alias,
    \\__fread_chk, __fread_chk_warn, __fread_unlocked_alias, __fread_unlocked_chk,
    \\__fread_unlocked_chk_warn, __get_environ_ptr, __get_wenviron_ptr, __getc_unlocked_body,
    \\__getdelim, __gets_chk, __gets_warn, __hypotf16, __inf, __inff, __infinity, __infinityf,
    \\__infinityl, __infl, __iob_func, __iseqsig, __iseqsigf, __iseqsigf128, __iseqsigl, __isfinite,
    \\__isfinited, __isfinitef, __isfinitel, __isinf, __isinfd, __isinff, __isinfl, __isnan, __isnand,
    \\__isnand128, __isnand32, __isnand64, __isnanf, __isnanl, __isnormal, __isnormald, __isnormalf,
    \\__isnormall, __isoc23_fscanf, __isoc23_scanf, __isoc23_sscanf, __isoc23_strtoimax,
    \\__isoc23_strtol, __isoc23_strtol_l, __isoc23_strtoll, __isoc23_strtoll_l, __isoc23_strtoul,
    \\__isoc23_strtoul_l, __isoc23_strtoull, __isoc23_strtoull_l, __isoc23_strtoumax, __isoc23_vfscanf,
    \\__isoc23_vscanf, __isoc23_vsscanf, __isoc23_wcstoimax, __isoc23_wcstoumax, __isoc99_fscanf,
    \\__isoc99_scanf, __isoc99_sscanf, __isoc99_vfscanf, __isoc99_vscanf, __isoc99_vsscanf,
    \\__issignaling, __issignalingf, __issignalingf128, __issignalingl, __isthreaded,
    \\__libc_ptrchk_strbuf_chk, __local_stdio_printf_options, __local_stdio_scanf_options,
    \\__longjmp_chk, __lwp_gettcb_fast, __lwp_settcb, __math_errhandling, __mbstowcs_chk,
    \\__mbstowcs_nulldst, __memccpy_ptrchk, __memcmpeq, __memcpy_chk, __memcpy_ptrchk, __memmove_chk,
    \\__memmove_ptrchk, __mempcpy, __memset_chk, __memset_explicit_chk, __memset_ptrchk,
    \\__mingw_aligned_free, __mingw_aligned_malloc, __mingw_aligned_msize,
    \\__mingw_aligned_offset_malloc, __mingw_aligned_offset_realloc, __mingw_aligned_realloc,
    \\__mingw_asprintf, __mingw_bos, __mingw_bos_cond_chk, __mingw_bos_known, __mingw_bos_ptr_chk,
    \\__mingw_bos_ptr_chk_warn, __mingw_call_fgets, __mingw_call_fread, __mingw_call_gets_warn,
    \\__mingw_call_memcpy_s, __mingw_call_ms_sprintf, __mingw_call_ms_vsprintf, __mingw_call_snprintf,
    \\__mingw_call_sprintf, __mingw_call_tmpnam, __mingw_call_vsnprintf, __mingw_call_vsprintf,
    \\__mingw_call_wcscat, __mingw_call_wcscpy, __mingw_fprintf, __mingw_fscanf, __mingw_fwprintf,
    \\__mingw_fwscanf, __mingw_get_crt_info, __mingw_longjmp, __mingw_printf, __mingw_raise_matherr,
    \\__mingw_scanf, __mingw_setjmp, __mingw_setusermatherr, __mingw_snprintf, __mingw_snwprintf,
    \\__mingw_sprintf, __mingw_sscanf, __mingw_str_free, __mingw_str_utf8_wide, __mingw_str_wide_utf8,
    \\__mingw_strtod, __mingw_strtof, __mingw_strtold, __mingw_swprintf, __mingw_swscanf,
    \\__mingw_vasprintf, __mingw_vfprintf, __mingw_vfscanf, __mingw_vfwprintf, __mingw_vfwscanf,
    \\__mingw_vprintf, __mingw_vscanf, __mingw_vsnprintf, __mingw_vsnwprintf, __mingw_vsprintf,
    \\__mingw_vsscanf, __mingw_vswprintf, __mingw_vswscanf, __mingw_vwprintf, __mingw_vwscanf,
    \\__mingw_wcstod, __mingw_wcstof, __mingw_wcstold, __mingw_wprintf, __mingw_wscanf, __mode__,
    \\__ms_fprintf, __ms_fscanf, __ms_fwprintf, __ms_fwscanf, __ms_printf, __ms_scanf, __ms_snprintf,
    \\__ms_snwprintf, __ms_sprintf, __ms_sscanf, __ms_swprintf, __ms_swscanf, __ms_vfprintf,
    \\__ms_vfscanf, __ms_vfwprintf, __ms_vfwscanf, __ms_vprintf, __ms_vscanf, __ms_vsnprintf,
    \\__ms_vsnwprintf, __ms_vsprintf, __ms_vsscanf, __ms_vswprintf, __ms_vswscanf, __ms_vwprintf,
    \\__ms_vwscanf, __ms_wprintf, __ms_wscanf, __nan, __nanf, __nextafterf16, __nldbl_nexttowardf,
    \\__obstack_printf_chk, __obstack_vprintf_chk, __off_t, __overflow, __p___argc, __p___argv,
    \\__p___wargv, __p__amblksiz, __p__environ, __p__fmode, __p__osplatform, __p__osver, __p__pgmptr,
    \\__p__wenviron, __p__winmajor, __p__winminor, __p__winver, __p__wpgmptr, __posix_getopt,
    \\__prefetch, __printf_chk, __printflike, __ptrcheck_abi_assume_single, __ptsname_r_chk,
    \\__putc_unlocked_body, __qsort_r_compat, __realpath_alias, __realpath_chk, __realpath_chk_warn,
    \\__rintf16, __roundf16, __sF, __scanflike, __setusermatherr, __signbit, __signbitd, __signbitd128,
    \\__signbitd32, __signbitd64, __signbitf, __signbitl, __sigsetjmp, __sincos, __sincos_stret,
    \\__sincosf, __sincosf_stret, __sincospi, __sincospi_stret, __sincospif, __sincospif_stret, __sinpi,
    \\__sinpif, __sized_by_or_null, __snprintf_chk, __sprintf_chk, __sputc, __sqrtf16, __srget,
    \\__ssp_bos, __ssp_bos_icheck2_restrict, __ssp_bos_icheck3, __ssp_bos_icheck3_restrict,
    \\__ssp_check_iovec, __ssp_overlap, __ssp_real, __ssp_redirect, __ssp_redirect0, __ssp_redirect_raw,
    \\__ssp_redirect_raw_impl, __stack_chk_fail, __stderr, __stderrp, __stdin, __stdinp,
    \\__stdio_common_vfprintf, __stdio_common_vfprintf_p, __stdio_common_vfprintf_s,
    \\__stdio_common_vfscanf, __stdio_common_vfwprintf, __stdio_common_vfwprintf_s,
    \\__stdio_common_vfwscanf, __stdio_common_vsnprintf_s, __stdio_common_vsnwprintf_s,
    \\__stdio_common_vsprintf, __stdio_common_vsprintf_p, __stdio_common_vsprintf_s,
    \\__stdio_common_vsscanf, __stdio_common_vswprintf, __stdio_common_vswprintf_s,
    \\__stdio_common_vswscanf, __stdout, __stdoutp, __stpcpy, __stpcpy_chk, __stpncpy, __stpncpy_alias,
    \\__stpncpy_chk, __strcat_chk, __strcpy_chk, __strftimelike, __strlcat_alias, __strlcat_chk,
    \\__strlcat_ptrchk, __strlcpy_alias, __strlcpy_chk, __strlcpy_ptrchk, __strncat_chk, __strncpy_chk,
    \\__strtod, __strtok_r, __svfscanf, __swap16gen, __swap16md, __swap32gen, __swap32md, __swap64gen,
    \\__swap64md, __swbuf, __swprintf_l, __sym_compat, __sys_errlist, __sys_nerr, __sysconf, __tanpi,
    \\__tanpif, __threadhandle, __threadid, __timezone, __truncf16, __typeof, __tzname, __uflow,
    \\__uint16_identity, __uint32_identity, __uint64_identity, __va_arg_pack, __vasprintf_chk,
    \\__vdprintf_chk, __vfprintf_chk, __vprintf_chk, __vsnprintf_chk, __vsprintf_chk, __vswprintf_l,
    \\__warnattr, __warning__, __wasi_args_get, __wasi_args_sizes_get, __wasi_clock_res_get,
    \\__wasi_clock_time_get, __wasi_environ_get, __wasi_environ_sizes_get, __wasi_fd_advise,
    \\__wasi_fd_allocate, __wasi_fd_close, __wasi_fd_datasync, __wasi_fd_fdstat_get,
    \\__wasi_fd_fdstat_set_flags, __wasi_fd_fdstat_set_rights, __wasi_fd_filestat_get,
    \\__wasi_fd_filestat_set_size, __wasi_fd_filestat_set_times, __wasi_fd_pread,
    \\__wasi_fd_prestat_dir_name, __wasi_fd_prestat_get, __wasi_fd_pwrite, __wasi_fd_read,
    \\__wasi_fd_readdir, __wasi_fd_renumber, __wasi_fd_seek, __wasi_fd_sync, __wasi_fd_tell,
    \\__wasi_fd_write, __wasi_path_create_directory, __wasi_path_filestat_get,
    \\__wasi_path_filestat_set_times, __wasi_path_link, __wasi_path_open, __wasi_path_readlink,
    \\__wasi_path_remove_directory, __wasi_path_rename, __wasi_path_symlink, __wasi_path_unlink_file,
    \\__wasi_poll_oneoff, __wasi_proc_exit, __wasi_random_get, __wasi_sched_yield, __wasi_sock_accept,
    \\__wasi_sock_recv, __wasi_sock_send, __wasi_sock_shutdown, __wasi_thread_spawn,
    \\__wasm_first_page_end, __wcserror, __wcserror_s, __wcstombs_chk, __wctomb_alias, __wctomb_chk,
    \\__xpg_strerror_r, __zeroll, __zeroull, _abs64, _aligned_free, _aligned_malloc, _aligned_msize,
    \\_aligned_offset_malloc, _aligned_offset_realloc, _aligned_offset_recalloc, _aligned_realloc,
    \\_aligned_recalloc, _alloca, _atodbl, _atodbl_l, _atof_l, _atoflt, _atoflt_l, _atoi64, _atoi64_l,
    \\_atoi_l, _atol_l, _atoldbl, _atoldbl_l, _beep, _byteswap_uint64, _byteswap_ulong,
    \\_byteswap_ushort, _cabs, _chgsign, _chgsignf, _chgsignl, _copysign, _copysignf, _ctime32,
    \\_ctime32_s, _ctime64, _ctime64_s, _difftime32, _difftime64, _dupenv_s, _ecvt, _ecvt_s, _errno,
    \\_exit, _expand, _fclose_nolock, _fcloseall, _fcvt, _fcvt_s, _fdopen, _fflush_nolock,
    \\_fgetc_nolock, _fgetchar, _fgetwc_nolock, _fgetwchar, _filbuf, _fileno, _finite, _finitef,
    \\_flsbuf, _flushall, _fpclass, _fpclassf, _fprintf_l, _fprintf_p, _fprintf_p_l, _fprintf_s_l,
    \\_fputc_nolock, _fputchar, _fputwc_nolock, _fputwchar, _fread_nolock, _fread_nolock_s, _freea,
    \\_fscanf_l, _fscanf_s_l, _fseek_nolock, _fseeki64, _fseeki64_nolock, _fsopen, _ftell_nolock,
    \\_ftelli64, _ftelli64_nolock, _ftime32, _ftime32_s, _ftime64, _ftime64_s, _fullpath, _fwprintf_l,
    \\_fwprintf_p, _fwprintf_p_l, _fwprintf_s_l, _fwrite_nolock, _fwscanf_l, _fwscanf_s_l, _gcvt,
    \\_gcvt_s, _get_amblksiz, _get_daylight, _get_doserrno, _get_dstbias, _get_environ, _get_errno,
    \\_get_fmode, _get_heap_handle, _get_invalid_parameter_handler, _get_osplatform, _get_osver,
    \\_get_output_format, _get_pgmptr, _get_printf_count_output, _get_purecall_handler,
    \\_get_sbh_threshold, _get_timezone, _get_tzname, _get_wenviron, _get_winmajor, _get_winminor,
    \\_get_winver, _get_wpgmptr, _getc_nolock, _getmaxstdio, _getsystime, _getw, _getws, _getws_s,
    \\_gmtime32, _gmtime32_s, _gmtime64, _gmtime64_s, _heapadd, _heapchk, _heapmin, _heapset, _heapused,
    \\_heapwalk, _hypot, _hypotf, _i64toa, _i64toa_s, _i64tow, _i64tow_s, _isnan, _isnanf, _itoa,
    \\_itoa_s, _itow, _itow_s, _j0, _j1, _jn, _localtime32, _localtime32_s, _localtime64,
    \\_localtime64_s, _lock_file, _logb, _logbf, _longjmp, _lrotl, _lrotr, _ltoa, _ltoa_s, _ltow,
    \\_ltow_s, _lwp_setprivate, _makepath, _makepath_s, _matherr, _mb_cur_max_l, _mblen_l, _mbstowcs_l,
    \\_mbstowcs_s_l, _mbstrlen, _mbstrlen_l, _mbstrnlen, _mbstrnlen_l, _mbtowc_l, _memccpy, _memicmp,
    \\_memicmp_l, _mkgmtime, _mkgmtime32, _mkgmtime64, _mktime32, _mktime64, _msize, _nextafter,
    \\_nextafterf, _onexit, _pclose, _popen, _printf_l, _printf_p, _printf_p_l, _printf_s_l,
    \\_putc_nolock, _putenv, _putenv_s, _putw, _putws, _recalloc, _resetstkoflw, _rmtmp, _rotl, _rotl64,
    \\_rotr, _rotr64, _rtld_tls_allocate, _rtld_tls_free, _scalb, _scanf_l, _scanf_s_l, _scprintf,
    \\_scprintf_l, _scprintf_p, _scprintf_p_l, _scwprintf, _scwprintf_l, _scwprintf_p, _scwprintf_p_l,
    \\_searchenv, _searchenv_s, _set_SSE2_enable, _set_abort_behavior, _set_amblksiz, _set_doserrno,
    \\_set_errno, _set_error_mode, _set_fmode, _set_invalid_parameter_handler, _set_malloc_crt_max_wait,
    \\_set_output_format, _set_printf_count_output, _set_purecall_handler, _set_sbh_threshold,
    \\_seterrormode, _setheaphook, _setjmp, _setjmp3, _setjmpex, _setmaxstdio, _setsystime, _sleep,
    \\_snprintf, _snprintf_c, _snprintf_c_l, _snprintf_l, _snprintf_s, _snprintf_s_l, _snscanf,
    \\_snscanf_l, _snscanf_s, _snscanf_s_l, _snwprintf, _snwprintf_l, _snwprintf_s, _snwprintf_s_l,
    \\_snwscanf, _snwscanf_l, _snwscanf_s, _snwscanf_s_l, _spawnv, _spawnve, _spawnvp, _spawnvpe,
    \\_splitpath, _splitpath_s, _sprintf_l, _sprintf_p, _sprintf_p_l, _sprintf_s_l, _sscanf_l,
    \\_sscanf_s_l, _strcmpi, _strcoll_l, _strdate, _strdate_s, _strdup, _strerror, _strerror_s,
    \\_strftime_l, _stricmp, _stricmp_l, _stricoll, _stricoll_l, _strlwr, _strlwr_s, _strlwr_s_l,
    \\_strncat_s_l, _strncoll, _strncoll_l, _strncpy_s_l, _strnicmp, _strnicmp_l, _strnicoll,
    \\_strnicoll_l, _strnset, _strnset_l, _strnset_s, _strrev, _strset, _strset_l, _strset_s, _strtime,
    \\_strtime_s, _strtod_l, _strtof_l, _strtoi64, _strtoi64_l, _strtok_s_l, _strtol_l, _strtoui64,
    \\_strtoui64_l, _strtoul_l, _strupr, _strupr_l, _strupr_s, _strupr_s_l, _strxfrm_l, _swab,
    \\_swprintf, _swprintf_c, _swprintf_c_l, _swprintf_p, _swprintf_p_l, _swprintf_s_l, _swscanf_l,
    \\_swscanf_s_l, _tempnam, _time32, _time64, _timespec32_get, _timespec64_get, _tzset, _ui64toa,
    \\_ui64toa_s, _ui64tow, _ui64tow_s, _ultoa, _ultoa_s, _ultow, _ultow_s, _ungetc_nolock,
    \\_ungetwc_nolock, _unlink, _unlock_file, _vfprintf_l, _vfprintf_p, _vfprintf_p_l, _vfprintf_s_l,
    \\_vfscanf_l, _vfscanf_s_l, _vfwprintf_l, _vfwprintf_p, _vfwprintf_p_l, _vfwprintf_s_l, _vfwscanf_l,
    \\_vfwscanf_s_l, _vprintf_l, _vprintf_p, _vprintf_p_l, _vprintf_s_l, _vscanf_l, _vscanf_s_l,
    \\_vscprintf, _vscprintf_l, _vscprintf_p, _vscprintf_p_l, _vscwprintf, _vscwprintf_l, _vscwprintf_p,
    \\_vscwprintf_p_l, _vsnprintf, _vsnprintf_c, _vsnprintf_c_l, _vsnprintf_l, _vsnprintf_s,
    \\_vsnprintf_s_l, _vsnwprintf, _vsnwprintf_l, _vsnwprintf_s, _vsnwprintf_s_l, _vsnwscanf_s_l,
    \\_vsprintf_l, _vsprintf_p, _vsprintf_p_l, _vsprintf_s_l, _vsscanf_l, _vsscanf_s_l, _vswprintf,
    \\_vswprintf_c, _vswprintf_c_l, _vswprintf_p, _vswprintf_p_l, _vswprintf_s_l, _vswscanf_s_l,
    \\_vwprintf_l, _vwprintf_p, _vwprintf_p_l, _vwprintf_s_l, _vwscanf_s_l, _wasctime, _wasctime_s,
    \\_wcscoll_l, _wcsdup, _wcserror, _wcserror_s, _wcsftime_l, _wcsicmp, _wcsicmp_l, _wcsicoll,
    \\_wcsicoll_l, _wcslwr, _wcslwr_l, _wcslwr_s, _wcslwr_s_l, _wcsncat_s_l, _wcsncoll, _wcsncoll_l,
    \\_wcsncpy_l, _wcsncpy_s_l, _wcsnicmp, _wcsnicmp_l, _wcsnicoll, _wcsnicoll_l, _wcsnset, _wcsnset_s,
    \\_wcsnset_s_l, _wcsrev, _wcsset, _wcsset_s, _wcsset_s_l, _wcstod_l, _wcstof_l, _wcstoi64,
    \\_wcstoi64_l, _wcstok, _wcstok_s_l, _wcstol_l, _wcstombs_l, _wcstombs_s_l, _wcstoui64,
    \\_wcstoui64_l, _wcstoul_l, _wcsupr, _wcsupr_l, _wcsupr_s, _wcsupr_s_l, _wcsxfrm_l, _wctime,
    \\_wctime32, _wctime32_s, _wctime64, _wctime64_s, _wctime_s, _wctomb_l, _wctomb_s_l, _wdupenv_s,
    \\_wfdopen, _wfopen, _wfopen_s, _wfreopen, _wfreopen_s, _wfsopen, _wfullpath, _wgetenv, _wgetenv_s,
    \\_wmakepath, _wmakepath_s, _wperror, _wpopen, _wprintf_l, _wprintf_p, _wprintf_p_l, _wprintf_s_l,
    \\_wputenv, _wputenv_s, _wremove, _wscanf_l, _wscanf_s_l, _wsearchenv, _wsearchenv_s, _wspawnl,
    \\_wspawnle, _wspawnlp, _wspawnlpe, _wspawnv, _wspawnve, _wspawnvp, _wspawnvpe, _wsplitpath,
    \\_wsplitpath_s, _wstrdate, _wstrdate_s, _wstrtime, _wstrtime_s, _wsystem, _wtempnam, _wtmpnam,
    \\_wtmpnam_s, _wtof, _wtof_l, _wtoi, _wtoi64, _wtoi64_l, _wtoi_l, _wtol, _wtol_l, _xlocale, _y0,
    \\_y1, _yn, a64l, abort, abort2, abort_handler_s, abs, acos, acosd128, acosd32, acosd64, acosf,
    \\acosh, acoshd128, acoshd32, acoshd64, acoshf, acoshl, acosl, adjtime, aligned, aligned_alloc,
    \\alloca, arc4random, arc4random_addrandom, arc4random_buf, arc4random_stir, arc4random_uniform,
    \\asctime, asctime_r, asctime_s, asin, asind128, asind32, asind64, asinf, asinh, asinhd128,
    \\asinhd32, asinhd64, asinhf, asinhl, asinl, asprintf, asprintf_l, at_quick_exit, atan, atan2,
    \\atan2d128, atan2d32, atan2d64, atan2f, atan2l, atand128, atand32, atand64, atanf, atanh,
    \\atanhd128, atanhd32, atanhd64, atanhf, atanhl, atanl, atexit, atexit_b, atof, atof_l, atoi,
    \\atoi_l, atol, atol_l, atoll, atoll_l, basename, bcmp, bcopy, be16dec, be16enc, be32dec, be32enc,
    \\be64dec, be64enc, bintime2timespec, bintime2timeval, bintime_add, bintime_addx, bintime_sub,
    \\bsd_signal, bsearch, bsearch_b, bsearch_s, bswap16, bswap32, bswap64, bzero, call_once, calloc,
    \\calloc_conceal, canonicalize_file_name, cbrt, cbrtd128, cbrtd32, cbrtd64, cbrtf, cbrtl, ceil,
    \\ceild128, ceild32, ceild64, ceilf, ceill, cfree, cgetcap, cgetclose, cgetent, cgetfirst,
    \\cgetmatch, cgetnext, cgetnum, cgetset, cgetstr, cgetusedb, cgetustr, chgsign, clearenv, clearerr,
    \\clearerr_s, clearerr_unlocked, clock, clock_adjtime, clock_getcpuclockid, clock_getcpuclockid2,
    \\clock_getres, clock_getres32, clock_getres64, clock_gettime, clock_gettime32, clock_gettime64,
    \\clock_gettime_nsec_np, clock_nanosleep, clock_nanosleep32, clock_nanosleep64, clock_settime,
    \\clock_settime32, clock_settime64, consttime_memequal, cookie_close_function_t,
    \\cookie_read_function_t, cookie_seek_function_t, cookie_write_function_t, copysign, copysignd128,
    \\copysignd32, copysignd64, copysignf, copysignl, cos, cosd128, cosd32, cosd64, cosf, cosh,
    \\coshd128, coshd32, coshd64, coshf, coshl, cosl, cospi, cospif, cospil, cpu_getmcontext,
    \\cpu_mcontext_validate, cpu_setmcontext, csetexpandtc, ctermid, ctermid_r, ctime, ctime_r,
    \\ctime_rz, ctime_s, cuserid, daemon, daemonfd, daylight, decltype, dehumanize_number, devname,
    \\devname_r, difftime, div, dprintf, dprintf_l, drand48, drand48_r, drem, dremf, driverkit, dysize,
    \\ecvt, ecvt_r, erand48, erand48_r, erf, erfc, erfcd128, erfcd32, erfcd64, erfcf, erfcl, erfd128,
    \\erfd32, erfd64, erff, erfl, err, errc, errno, errx, exit, exp, exp10, exp10d128, exp10d32,
    \\exp10d64, exp10f, exp10l, exp2, exp2d128, exp2d32, exp2d64, exp2f, exp2l, expd128, expd32, expd64,
    \\expf, expl, explicit_bzero, explicit_memset, expm1, expm1d128, expm1d32, expm1d64, expm1f, expm1l,
    \\fabs, fabsd128, fabsd32, fabsd64, fabsf, fabsl, fclose, fcloseall, fcvt, fcvt_r, fdclose,
    \\fdevname, fdevname_r, fdim, fdimd128, fdimd32, fdimd64, fdimf, fdiml, fdopen, feof, feof_unlocked,
    \\ferror, ferror_unlocked, fflush, fflush_unlocked, ffs, ffsl, ffsll, fgetc, fgetc_unlocked,
    \\fgetchar, fgetln, fgetpos, fgetpos64, fgets, fgets_unlocked, fgetwc, fgetws, fileno,
    \\fileno_unlocked, filt_seltrue, finite, finitef, flockfile, floor, floord128, floord32, floord64,
    \\floorf, floorl, fls, flsl, flsll, flushall, fma, fmad128, fmad32, fmad64, fmaf, fmal, fmax,
    \\fmaxd128, fmaxd32, fmaxd64, fmaxf, fmaxl, fmemopen, fmin, fmind128, fmind32, fmind64, fminf,
    \\fminl, fmod, fmodd128, fmodd32, fmodd64, fmodf, fmodl, fmtcheck, fopen, fopen64, fopen_s,
    \\fopencookie, format, format_arg, fparseln, fpclass, fpos_t, fprintf, fprintf_l, fprintf_s, fpurge,
    \\fputc, fputc_unlocked, fputchar, fputs, fputs_unlocked, fputwc, fputws, fread, fread_s,
    \\fread_unlocked, free, free_aligned_sized, free_sized, freezero, freopen, freopen64, freopen_s,
    \\frexp, frexpd128, frexpd32, frexpd64, frexpf, frexpl, fscanf, fscanf_l, fscanf_s, fseek, fseeko,
    \\fseeko64, fsetpos, fsetpos64, ftell, ftello, ftello64, ftime, ftruncate, ftrylockfile, func,
    \\funlockfile, funopen, funopen2, futimes, fwprintf, fwprintf_s, fwrite, fwrite_unlocked, fwscanf,
    \\fwscanf_s, gamma, gamma_r, gammaf, gammaf_r, gcvt, getbsize, getc, getc_unlocked, getchar,
    \\getchar_unlocked, getdate, getdate_err, getdate_r, getdelim, getdevmajor, getenv, getenv_r,
    \\getenv_s, getiopolicy_np, getitimer, getline, getloadavg, getopt, getpriority, getprogname, getpt,
    \\getrlimit, getrusage, gets, gets_s, getsubopt, gettimeofday, getucontext, getw, getwc, getwchar,
    \\gmtime, gmtime_r, gmtime_s, grantpt, heapsort, heapsort_b, hmac, htonl, htons, humanize_number,
    \\hypot, hypotd128, hypotd32, hypotd64, hypotf, hypotl, ignore_handler_s, ilogb, ilogbd128,
    \\ilogbd32, ilogbd64, ilogbf, ilogbl, imaxabs, imaxdiv, index, initstate, initstate_r, ioctl, ios,
    \\iseqsig, isfinite, isinf, isinfd128, isinfd32, isinfd64, isinff, isnan, isnand128, isnand32,
    \\isnand64, isnanf, issignaling, iszero, itoa, j0, j0f, j1, j1f, jn, jnf, jrand48, jrand48_r,
    \\kevent, kevent1, kevent_fetch_changes, kevent_put_events, kfilter_register, kfilter_unregister,
    \\klist_fini, klist_init, klist_insert, klist_remove, knote, knote_clear_eof, knote_fdclose,
    \\knote_set_eof, kqueue, kqueue1, kqueue_init, l64a, l64a_r, labs, lcong48, lcong48_deterministic,
    \\lcong48_r, ldexp, ldexpd128, ldexpd32, ldexpd64, ldexpf, ldexpl, ldiv, le16dec, le16enc, le32dec,
    \\le32enc, le64dec, le64enc, lgamma, lgamma_r, lgammad128, lgammad32, lgammad64, lgammaf, lgammaf_r,
    \\lgammal, lgammal_r, llabs, lldiv, llrint, llrintd128, llrintd32, llrintd64, llrintf, llrintl,
    \\llround, llroundd128, llroundd32, llroundd64, llroundf, llroundl, lltoa, lltow, localtime,
    \\localtime_r, localtime_rz, localtime_s, log, log10, log10d128, log10d32, log10d64, log10f, log10l,
    \\log1p, log1pd128, log1pd32, log1pd64, log1pf, log1pl, log2, log2d128, log2d32, log2d64, log2f,
    \\log2l, logb, logbd128, logbd32, logbd64, logbf, logbl, logd128, logd32, logd64, logf, logl,
    \\longjmp, longjmperror, lrand48, lrand48_r, lrint, lrintd128, lrintd32, lrintd64, lrintf, lrintl,
    \\lround, lroundd128, lroundd32, lroundd64, lroundf, lroundl, lseek, ltoa, lutimes, macos, macosx,
    \\malloc, malloc_conceal, malloc_conf, malloc_type_aligned_alloc,
    \\malloc_type_aligned_alloc_backdeploy, malloc_type_calloc, malloc_type_calloc_backdeploy,
    \\malloc_type_free, malloc_type_free_backdeploy, malloc_type_malloc, malloc_type_malloc_backdeploy,
    \\malloc_type_posix_memalign, malloc_type_posix_memalign_backdeploy, malloc_type_realloc,
    \\malloc_type_realloc_backdeploy, malloc_type_valloc, malloc_type_valloc_backdeploy,
    \\malloc_type_zone_calloc, malloc_type_zone_calloc_backdeploy, malloc_type_zone_free,
    \\malloc_type_zone_free_backdeploy, malloc_type_zone_malloc, malloc_type_zone_malloc_backdeploy,
    \\malloc_type_zone_memalign, malloc_type_zone_memalign_backdeploy, malloc_type_zone_realloc,
    \\malloc_type_zone_realloc_backdeploy, malloc_type_zone_valloc, malloc_type_zone_valloc_backdeploy,
    \\matherr, mblen, mblen_l, mbstowcs, mbstowcs_l, mbstowcs_s, mbtowc, mbtowc_l, memalign,
    \\memalignment, memccpy, memchr, memcmp, memcpy, memcpy_s, memfrob, memicmp, memmem, memmove,
    \\memmove_s, mempcpy, memrchr, memset, memset_explicit, memset_pattern16, memset_pattern4,
    \\memset_pattern8, memset_s, mergesort, mergesort_b, mi_vector_hash, mingw_getsp,
    \\mingw_gettimeofday, mkdtemp, mkdtemps, mkostemp, mkostemp64, mkostemps, mkostemps64, mkostempsat,
    \\mkstemp, mkstemp64, mkstemps, mkstemps64, mktemp, mktime, mktime_z, mmap, modf, modfd128, modfd32,
    \\modfd64, modff, modfl, mrand48, mrand48_r, ms2bintime, nan, nand128, nand32, nand64, nanf, nanl,
    \\nanosleep, nanosleep32, nanosleep64, nearbyint, nearbyintd128, nearbyintd32, nearbyintd64,
    \\nearbyintf, nearbyintl, nextafter, nextafterd128, nextafterd32, nextafterd64, nextafterf,
    \\nextafterl, nexttoward, nexttowardd128, nexttowardd32, nexttowardd64, nexttowardf, nexttowardl,
    \\nonnull, nrand48, nrand48_r, ns2bintime, ntohl, ntohs, obstack_printf, obstack_vprintf, off_t,
    \\offsetof, offtime, offtime_r, on_exit, onexit, open_memstream, open_wmemstream, optarg, opterr,
    \\optind, optopt, pclose, perror, popcount, popcount32, popcount64, popcountl, popcountll, popen,
    \\popenve, posix2time, posix2time_z, posix_memalign, posix_openpt, pow, pow10, pow10f, pow10l, powf,
    \\powl, printf, printf_l, printf_s, program_invocation_name, program_invocation_short_name, pselect,
    \\psort, psort_b, psort_r, ptsname, ptsname_r, putc, putc_unlocked, putchar, putchar_unlocked,
    \\putenv, puts, putw, putwc, putwchar, qabs, qdiv, qecvt, qecvt_r, qfcvt, qfcvt_r, qgcvt, qsort,
    \\qsort_b, qsort_r, qsort_s, quantexpd128, quantexpd32, quantexpd64, quantized128, quantized32,
    \\quantized64, quick_exit, radixsort, rand, rand_r, rand_s, random, random_r, rawmemchr, realloc,
    \\reallocarr, reallocarray, reallocf, realpath, recallocarray, remainder, remainderd128,
    \\remainderd32, remainderd64, remainderf, remainderl, remove, remquo, remquof, remquol, rename,
    \\renameat, renameat2, renameatx_np, renamex_np, rewind, rindex, rint, rintd128, rintd32, rintd64,
    \\rintf, rintl, rinttol, rmtmp, round, roundd128, roundd32, roundd64, roundf, roundl, roundtol,
    \\rpmatch, samequantumd128, samequantumd32, samequantumd64, scalb, scalbf, scalbln, scalblnd128,
    \\scalblnd32, scalblnd64, scalblnf, scalblnl, scalbn, scalbnd128, scalbnd32, scalbnd64, scalbnf,
    \\scalbnl, scanf, scanf_l, scanf_s, secure_getenv, seed48, seed48_deterministic, seed48_r,
    \\selcommon, seldestroy, select, selinit, selnotify, selrecord, selrecord_knote, selremove_knote,
    \\selsysinit, seltrue_filtops, set_constraint_handler_s, setbuf, setbuffer, setenv, setiopolicy_np,
    \\setitimer, setjmp, setkey, setlinebuf, setpriority, setproctitle, setprogname, setrlimit,
    \\setstate, setstate_r, settimeofday, setucontext, setvbuf, shquote, shquotev, sigabbrev_np,
    \\sigdescr_np, siglongjmp, signal, signgam, significand, significandf, sigqueue, sigqueueinfo,
    \\sigsetjmp, sin, sincos, sincosf, sincosl, sind128, sind32, sind64, sinf, sinh, sinhd128, sinhd32,
    \\sinhd64, sinhf, sinhl, sinl, sinpi, sinpif, sinpil, size_t, snprintf, snprintf_l, snprintf_ss,
    \\snwprintf, sprintf, sprintf_l, sprintf_s, sqrt, sqrtd128, sqrtd32, sqrtd64, sqrtf, sqrtl,
    \\sradixsort, srand, srand48, srand48_deterministic, srand48_r, srand_deterministic, sranddev,
    \\srandom, srandom_deterministic, srandom_r, srandomdev, sscanf, sscanf_l, sscanf_s, ssize_t, st,
    \\stderr, stdin, stdout, stime, stpcpy, stpncpy, strcasecmp, strcasecmp_l, strcasestr, strcasestr_l,
    \\strcat, strcat_s, strchr, strchrnul, strcmp, strcmpi, strcoll, strcoll_l, strcpy, strcpy_s,
    \\strcspn, strdup, strerror, strerror_l, strerror_r, strerror_s, strerrordesc_np, strerrorname_np,
    \\stresep, strfromd, strfromf, strfromf128, strfromf128x, strfromf16, strfromf32, strfromf32x,
    \\strfromf64, strfromf64x, strfroml, strfry, strftime, strftime_l, strftime_lz, strftime_z, stricmp,
    \\strlcat, strlcpy, strlen, strlwr, strlwr_l, strmode, strncasecmp, strncasecmp_l, strncat,
    \\strncat_s, strncmp, strncpy, strncpy_s, strndup, strnicmp, strnlen, strnlen_s, strnset, strnstr,
    \\strpbrk, strptime, strptime_l, strrchr, strrev, strsep, strset, strsignal, strsignal_r, strspn,
    \\strstr, strsuftoll, strsuftollx, strtod, strtod_l, strtof, strtof128, strtof128_l, strtof128x,
    \\strtof128x_l, strtof16, strtof16_l, strtof32, strtof32_l, strtof32x, strtof32x_l, strtof64,
    \\strtof64_l, strtof64x, strtof64x_l, strtof_l, strtoi, strtoi_l, strtoimax, strtoimax_l, strtok,
    \\strtok_r, strtok_s, strtol, strtol_l, strtold, strtold_l, strtoll, strtoll_l, strtonum, strtoq,
    \\strtoq_l, strtou, strtou_l, strtoul, strtoul_l, strtoull, strtoull_l, strtoumax, strtoumax_l,
    \\strtouq, strtouq_l, strupr, strverscmp, strxfrm, strxfrm_l, suboptarg, swab, swprintf, swprintf_s,
    \\swscanf, swscanf_s, sys_errlist, sys_nerr, system, tan, tand128, tand32, tand64, tanf, tanh,
    \\tanhd128, tanhd32, tanhd64, tanhf, tanhl, tanl, tanpi, tanpif, tanpil, tempnam, tgamma,
    \\tgammad128, tgammad32, tgammad64, tgammaf, tgammal, throw, time, time2posix, time2posix_z, timegm,
    \\timelocal, timelocal_z, timeoff, timer_create, timer_delete, timer_getoverrun, timer_gettime,
    \\timer_oshandle_np, timer_settime, timespec2bintime, timespec_get, timespec_getres, timespecaddok,
    \\timespecsubok, timeval2bintime, timezone, timingsafe_bcmp, timingsafe_memcmp, tmpfile, tmpfile64,
    \\tmpfile_s, tmpnam, tmpnam_r, tmpnam_s, trunc, truncate, truncd128, truncd32, truncd64, truncf,
    \\truncl, ttydefchars, ttyslot, tvos, tzalloc, tzfree, tzgetgmtoff, tzgetname, tzname, tzset,
    \\tzsetwall, uabs, ulabs, ullabs, ulltoa, ulltow, ultoa, umaxabs, ungetc, ungetwc, unlink, unlockpt,
    \\unsetenv, us2bintime, utimes, valloc, vasprintf, vasprintf_l, vdprintf, vdprintf_l, verr, verrc,
    \\verrx, vfprintf, vfprintf_l, vfprintf_s, vfscanf, vfscanf_l, vfscanf_s, vfwprintf, vfwprintf_s,
    \\vfwscanf, vfwscanf_s, visionos, vprintf, vprintf_l, vprintf_s, vscanf, vscanf_l, vscanf_s,
    \\vsnprintf, vsnprintf_l, vsnprintf_s, vsnprintf_ss, vsnwprintf, vsprintf, vsprintf_l, vsprintf_s,
    \\vsscanf, vsscanf_l, vsscanf_s, vswprintf, vswprintf_s, vswscanf, vswscanf_s, vwarn, vwarnc,
    \\vwarnx, vwprintf, vwprintf_s, vwscanf, vwscanf_s, wait, wait3, wait4, waitid, waitpid, warn,
    \\warnc, warnx, watchos, wcscat, wcscat_s, wcschr, wcscmp, wcscoll, wcscpy, wcscpy_s, wcscspn,
    \\wcsdup, wcsftime, wcsicmp, wcsicoll, wcslen, wcslwr, wcsncat, wcsncat_s, wcsncmp, wcsncpy,
    \\wcsncpy_s, wcsnicmp, wcsnlen, wcsnlen_s, wcsnset, wcspbrk, wcsrchr, wcsrev, wcsset, wcsspn,
    \\wcsstr, wcstod, wcstof, wcstoimax, wcstoimax_l, wcstok, wcstok_s, wcstol, wcstold, wcstombs,
    \\wcstombs_l, wcstombs_s, wcstoul, wcstoumax, wcstoumax_l, wcsupr, wcsxfrm, wctomb, wctomb_l,
    \\wctomb_s, wprintf, wprintf_s, wscanf, wscanf_s, wtoll, y0, y0f, y1, y1f, yn, ynf,
    \\
;

/// No HarfBuzz API symbols are optional for this provider.
const provider_optional = "";

/// No HarfBuzz declarations are excluded from provider routing.
const provider_excluded = "";

/// Creates the linked-build loader core so this SDK's `LoadSource` and `LoadError` types are shared.
/// Runtime-loaded builds use the loader instance generated with their dispatch.
pub fn createCoreModule(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) *std.Build.Module {
    return b.createModule(.{
        .root_source_file = b.path("runtime/loader.zig"),
        .target = target,
        .optimize = optimize,
        // The Unix backend calls `dlopen`, which is libc. Nothing in this module
        // is compiled into a linked build, so this costs nothing there.
        .link_libc = true,
    });
}

/// Creates the runtime-loaded `c` module for the supplied translation.
/// The generator reads that target's translation output to produce its dispatch.
pub fn createModule(
    b: *std.Build,
    translate: *std.Build.Step.TranslateC,
    target: std.Build.ResolvedTarget,
    optimize: std.lang.Optimize,
) *std.Build.Module {
    const core = createCoreModule(b, target, optimize);

    const library = b.createModule(.{
        .root_source_file = b.path("runtime/library.zig"),
        .target = target,
        .optimize = optimize,
    });
    library.addImport("rt", core);

    return createDispatchModule(b, translate, target, optimize, core, library);
}

const GeneratedSources = struct {
    native: std.Build.LazyPath,
    dispatch: std.Build.LazyPath,
};

fn createDispatchModule(
    b: *std.Build,
    translate: *std.Build.Step.TranslateC,
    target: std.Build.ResolvedTarget,
    optimize: std.lang.Optimize,
    core: *std.Build.Module,
    library: *std.Build.Module,
) *std.Build.Module {
    const sources = generateDispatch(b, translate, target);

    const dispatch = b.createModule(.{
        .root_source_file = sources.dispatch,
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    dispatch.addImport("rt", core);
    dispatch.addImport("library", library);
    // Use the patched translation so macro-expanded references resolve through dispatch wrappers.
    // Re-export its declarations to preserve type identity.
    const native = b.createModule(.{
        .root_source_file = sources.native,
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    native.addImport("c_routed", dispatch);
    dispatch.addImport("c_native", native);
    dispatch.addCSourceFiles(.{
        .files = &.{"runtime/sync.c"},
        .flags = &.{b.fmt("-DRT_SYNC_PREFIX={s}", .{sync_prefix})},
        .language = .c,
    });
    return dispatch;
}

/// Runs the generator on this target's translation output.
fn generateDispatch(
    b: *std.Build,
    translate: *std.Build.Step.TranslateC,
    target: std.Build.ResolvedTarget,
) GeneratedSources {
    const generator = b.addExecutable(.{
        .name = b.fmt("harfbuzz-runtime-generate-{s}", .{
            target.result.zigTriple(b.allocator) catch @panic("unspellable target"),
        }),
        .root_module = b.createModule(.{
            .root_source_file = b.path("runtime/generate.zig"),
            .target = b.graph.host,
            .optimize = .debug,
        }),
    });

    const run = b.addRunArtifact(generator);
    run.addArg("--library");
    run.addArg("harfbuzz");
    run.addArg("--translate");
    run.addFileArg2(translate.getOutput(), .{});
    if (libc_noise.len != 0) {
        run.addArg("--noise");
        run.addArg(libc_noise);
    }
    if (provider_optional.len != 0) {
        run.addArg("--optional");
        run.addArg(provider_optional);
    }
    if (provider_excluded.len != 0) {
        run.addArg("--exclude");
        run.addArg(provider_excluded);
    }
    run.addArg("--native-output");
    const native_source = run.addOutputFileArg2("native.zig", .{});
    run.addArg("--output");
    const dispatch_source = run.addOutputFileArg2("dispatch.zig", .{});
    return .{ .native = native_source, .dispatch = dispatch_source };
}
