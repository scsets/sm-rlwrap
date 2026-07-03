#!/bin/sh
# install-rlwrap-smartos.ksh --- Build rlwrap on SmartOS.
#
# Copyright (C) 2026 scs
# Author: scs
# Created: 2026-07-03
# Date: 2026-07-03
# Version: 0.1.0
# Keywords: smartos, rlwrap, readline, installer, ksh93
#
# Commentary:
#
# Build and install Hans Lub's rlwrap from the upstream release tarball on a
# SmartOS global zone whose pkgsrc tools live under /opt/tools.  The release
# tarball is used instead of a git checkout because it already carries the
# generated configure script, which keeps the normal dependency set small.
#
# Code:

# This file is intentionally self-contained: a fresh repository has no shared
# bootstrap library yet, so the small /bin/sh preamble hands execution to ksh93.
if [ -z "${SM_RLWRAP_KSH93_BOOTSTRAPPED:-}" ]; then
    SM_RLWRAP_BOOTSTRAP_PREFIX=${SM_RLWRAP_TOOLS_PREFIX:-/opt/tools}

    if [ -x "${SM_RLWRAP_BOOTSTRAP_PREFIX}/bin/ksh93" ]; then
        SM_RLWRAP_KSH93_BOOTSTRAPPED=1 exec "${SM_RLWRAP_BOOTSTRAP_PREFIX}/bin/ksh93" "$0" "$@"
    fi

    if SM_RLWRAP_KSH93=$(command -v ksh93 2>/dev/null); then
        SM_RLWRAP_KSH93_BOOTSTRAPPED=1 exec "${SM_RLWRAP_KSH93}" "$0" "$@"
    fi

    printf '%s\n' "install-rlwrap-smartos.ksh: ksh93 was not found." >&2
    printf '%s\n' "Install ksh93 under ${SM_RLWRAP_BOOTSTRAP_PREFIX}/bin or put ksh93 in PATH." >&2
    exit 127
fi

# The script name is used in diagnostics and in the installed manual page name.
typeset -r SCRIPT_NAME=${0##*/}

# The original script path is saved before the build step changes directory.
typeset SCRIPT_PATH=$0
case "$SCRIPT_PATH" in
    /*) ;;
    *) SCRIPT_PATH=$(pwd)/$SCRIPT_PATH ;;
esac
typeset -r SCRIPT_PATH

# The script version documents the installer, not the rlwrap version.
typeset -r SCRIPT_VERSION='0.1.0'

# SmartOS pkgsrc tools are expected under this prefix unless the user overrides
# SM_RLWRAP_TOOLS_PREFIX or passes --tools-prefix after ksh93 has started.
typeset -r DEFAULT_TOOLS_PREFIX='/opt/tools'

# The default install prefix matches the user's stated global-zone layout.
typeset -r DEFAULT_INSTALL_PREFIX='/opt/tools'

# The upstream release verified while writing this installer.
typeset -r DEFAULT_RLWRAP_VERSION='0.48'

# The upstream release tarball URL from hanslub42/rlwrap.
typeset -r DEFAULT_SOURCE_URL='https://github.com/hanslub42/rlwrap/releases/download/v0.48/rlwrap-0.48.tar.gz'

# GitHub's release asset digest for rlwrap-0.48.tar.gz.
typeset -r DEFAULT_SOURCE_SHA256='cdf69074a216a8284574dddd145dd046c904ad5330a616e0eed53c9043f2ecbc'

# The build tree lives outside /opt/tools so failed builds do not leave partial
# files inside the tools prefix.
typeset -r DEFAULT_BUILD_ROOT='/var/tmp/sm-rlwrap-build'

# The default build avoids the optional libptytty dependency.
typeset -r DEFAULT_LIBPTYTTY_MODE='without'

# Mutable installer settings.  These are populated by parse_arguments.
typeset TOOLS_PREFIX=${SM_RLWRAP_TOOLS_PREFIX:-$DEFAULT_TOOLS_PREFIX}
typeset INSTALL_PREFIX=${SM_RLWRAP_INSTALL_PREFIX:-$DEFAULT_INSTALL_PREFIX}
typeset BUILD_ROOT=${SM_RLWRAP_BUILD_ROOT:-$DEFAULT_BUILD_ROOT}
typeset RLWRAP_VERSION=$DEFAULT_RLWRAP_VERSION
typeset SOURCE_URL=$DEFAULT_SOURCE_URL
typeset SOURCE_SHA256=$DEFAULT_SOURCE_SHA256
typeset LIBPTYTTY_MODE=$DEFAULT_LIBPTYTTY_MODE
typeset JOBS=${SM_RLWRAP_JOBS:-1}
typeset RUN_CHECKS=no
typeset KEEP_BUILD=no
typeset DRY_RUN=no
typeset FORCE_NON_SMARTOS=no
typeset INSTALL_SELF=no

# Tool paths are discovered after PATH is set to prefer /opt/tools.
typeset FETCH_TOOL=
typeset FETCH_MODE=
typeset GZIP_TOOL=
typeset TAR_TOOL=
typeset MAKE_TOOL=
typeset SHA256SUM_TOOL=
typeset CC_TOOL=

function die {
    # Purpose: Print a fatal diagnostic and stop the installer.
    # Arguments: Diagnostic text.
    # Return value: Does not return.
    # Side effects: Writes to standard error and exits non-zero.
    print -r -- "${SCRIPT_NAME}: $*" >&2
    exit 1
}

function warn {
    # Purpose: Print a non-fatal diagnostic.
    # Arguments: Warning text.
    # Return value: Always succeeds.
    # Side effects: Writes to standard error.
    print -r -- "${SCRIPT_NAME}: warning: $*" >&2
}

function notice {
    # Purpose: Print a normal progress message.
    # Arguments: Message text.
    # Return value: Always succeeds.
    # Side effects: Writes to standard output.
    print -r -- "==> $*"
}

function usage {
    # Purpose: Show a short command-line summary.
    # Arguments: None.
    # Return value: Always succeeds.
    # Side effects: Writes to standard output.
    cat <<USAGE
Usage: ${SCRIPT_NAME} [options]

Installer version: ${SCRIPT_VERSION}

Build and install rlwrap ${DEFAULT_RLWRAP_VERSION} from hanslub42/rlwrap on a
SmartOS global zone.  Build tools and installed files default to /opt/tools.

Options:
  --prefix DIR              Install rlwrap under DIR (default: /opt/tools)
  --tools-prefix DIR        Find build tools, headers, and libraries under DIR
  --build-root DIR          Build under DIR (default: /var/tmp/sm-rlwrap-build)
  --version VERSION         Use the standard GitHub URL for VERSION
  --url URL                 Download a custom source tarball URL
  --sha256 HEX              Expected SHA-256 for the source tarball
  --no-sha256               Skip source checksum verification
  --jobs N                  Parallel make jobs (default: 1)
  --with-libptytty          Require upstream libptytty support
  --without-libptytty       Use rlwrap's built-in pty code (default)
  --run-checks              Run make check before make install
  --keep-build              Leave the build directory in place
  --install-self            Copy this installer into PREFIX/sbin
  --dry-run                 Print the major actions without running them
  --force-non-smartos       Allow execution outside SmartOS/global zone
  --help                    Show this help text
  --man                     Show the full manual page

Environment:
  CC, CPPFLAGS, CFLAGS, LDFLAGS, LIBS, MAKEFLAGS are honored by configure/make.
USAGE
}

function manpage {
    # Purpose: Emit the authoritative manual page for this script.
    # Arguments: None.
    # Return value: Always succeeds.
    # Side effects: Writes roff manual text to standard output.
    cat <<'MANPAGE'
.TH INSTALL-RLWRAP-SMARTOS.KSH 8 "2026-07-03" "0.1.0" "System Administration"
.SH NAME
install-rlwrap-smartos.ksh \- build and install rlwrap on a SmartOS global zone
.SH SYNOPSIS
.B install-rlwrap-smartos.ksh
[\fB--prefix\fR \fIDIR\fR]
[\fB--tools-prefix\fR \fIDIR\fR]
[\fB--build-root\fR \fIDIR\fR]
[\fB--version\fR \fIVERSION\fR]
[\fB--url\fR \fIURL\fR]
[\fB--sha256\fR \fIHEX\fR]
[\fB--jobs\fR \fIN\fR]
[\fB--run-checks\fR]
[\fB--install-self\fR]
.SH DESCRIPTION
.B install-rlwrap-smartos.ksh
downloads the upstream rlwrap release tarball from
.B hanslub42/rlwrap,
verifies its SHA-256 checksum when a checksum is known, configures it to use
headers and libraries from the SmartOS pkgsrc tools prefix, builds it, installs
it, installs this manual page, and runs a small
.B rlwrap --version
smoke test.
.PP
The default layout is intentionally simple:
.RS
.IP \(bu 2
tools prefix:
.B /opt/tools
.IP \(bu 2
install prefix:
.B /opt/tools
.IP \(bu 2
build root:
.B /var/tmp/sm-rlwrap-build
.RE
.PP
The normal build uses the release tarball rather than a git checkout.  The
release tarball already contains
.B configure,
so the default build does not require Autoconf or Automake.
.SH OPTIONS
.TP
.BI --prefix " DIR"
Install rlwrap under
.IR DIR .
The default is
.BR /opt/tools .
.TP
.BI --tools-prefix " DIR"
Search for tools, headers, and libraries under
.IR DIR .
The default is
.BR /opt/tools .
The script prepends
.BI DIR /bin
and
.BI DIR /sbin
to
.BR PATH .
.TP
.BI --build-root " DIR"
Use
.IR DIR
for downloads and extracted source trees.
.TP
.BI --version " VERSION"
Build the standard GitHub release tarball for
.IR VERSION .
For versions other than 0.48, pass
.B --sha256
with the release asset digest if you want checksum verification.
.TP
.BI --url " URL"
Download a custom source tarball.  This is useful when testing a new upstream
release before changing the script default.
.TP
.BI --sha256 " HEX"
Expected SHA-256 digest for the source tarball.
.TP
.B --no-sha256
Skip checksum verification.  This is less safe and should be used only when
testing a local or newly published tarball whose digest has not yet been
recorded.
.TP
.BI --jobs " N"
Pass
.BI -j N
to make.  The default is 1 for predictable global-zone behavior.
.TP
.B --with-libptytty
Use rlwrap's upstream default and require libptytty.
.TP
.B --without-libptytty
Configure rlwrap with
.BR --without-libptytty .
This is the default because it avoids an optional dependency on SmartOS.
.TP
.B --run-checks
Run
.B make check
before
.BR make install .
.TP
.B --keep-build
Keep the source tree after installation.
.TP
.B --install-self
Copy this installer into
.BI PREFIX /sbin
after rlwrap is installed.
.TP
.B --dry-run
Print major actions without running them.
.TP
.B --force-non-smartos
Allow execution outside a SmartOS global zone.  This is mainly for testing the
script itself.
.TP
.B --man
Print this manual page.
.SH DEPENDENCIES
The normal release-tarball build expects these tools or libraries to be present
under the tools prefix:
.RS
.IP \(bu 2
ksh93
.IP \(bu 2
curl or wget
.IP \(bu 2
gzip and tar, preferably GNU tar as
.B gtar
.IP \(bu 2
GNU make as
.B gmake
or a compatible
.B make
.IP \(bu 2
gcc or another C compiler
.IP \(bu 2
GNU Readline headers and library
.IP \(bu 2
a terminal library such as ncurses, curses, tinfo, tinfow, or termcap
.IP \(bu 2
sha256sum when checksum verification is enabled
.RE
.PP
Perl or Python is only needed if you plan to use rlwrap filters at runtime.
.SH EXAMPLES
Install rlwrap into the normal SmartOS tools prefix:
.IP
.EX
# ./install-rlwrap-smartos.ksh
.EE
.PP
Build with four make jobs:
.IP
.EX
# ./install-rlwrap-smartos.ksh --jobs 4
.EE
.PP
Test the next upstream release while keeping the installed prefix unchanged:
.IP
.EX
# ./install-rlwrap-smartos.ksh \\
    --version 0.49 \\
    --sha256 expected_release_asset_digest_here
.EE
.PP
Use a local staging prefix:
.IP
.EX
$ ./install-rlwrap-smartos.ksh \\
    --prefix "$HOME/opt/rlwrap" \\
    --force-non-smartos
.EE
.SH FILES
.TP
.BI /opt/tools/bin/rlwrap
Default installed rlwrap executable.
.TP
.BI /opt/tools/man/man8/install-rlwrap-smartos.ksh.8
Default installed manual page for this installer.
.TP
.BI /var/tmp/sm-rlwrap-build
Default build root.
.SH EXIT STATUS
.B install-rlwrap-smartos.ksh
exits 0 on success and non-zero when a prerequisite, download, build, install,
or smoke test step fails.
.SH NOTES
The installer defaults to
.B --without-libptytty
because rlwrap still has built-in pty support and this keeps the SmartOS
dependency set smaller.  Pass
.B --with-libptytty
if you deliberately installed libptytty and want to require it.
.SH SEE ALSO
.BR rlwrap (1),
.BR pkgin (1),
.BR make (1),
.BR configure (1)
.SH AUTHORS
Installer by SCS.  rlwrap is maintained upstream by Hans Lub.
MANPAGE
}

function command_path {
    # Purpose: Resolve a command name using the current PATH.
    # Arguments: One command name.
    # Return value: Prints the resolved path and returns 0, or returns 1.
    # Side effects: None.
    typeset name=$1
    typeset path

    path=$(whence -p "$name" 2>/dev/null) || return 1
    [[ -n $path ]] || return 1
    print -r -- "$path"
}

function require_value {
    # Purpose: Validate that an option has a following value.
    # Arguments: Option name and candidate value.
    # Return value: Succeeds when the value is present.
    # Side effects: May exit through die.
    typeset option=$1
    typeset value=${2:-}

    [[ -n $value && $value != --* ]] || die "${option} requires a value"
}

function require_positive_integer {
    # Purpose: Validate a positive decimal integer.
    # Arguments: Option name and candidate value.
    # Return value: Succeeds when the value is a positive integer.
    # Side effects: May exit through die.
    typeset option=$1
    typeset value=$2

    [[ $value == +([0-9]) ]] || die "${option} requires a positive integer"
    (( value > 0 )) || die "${option} requires a positive integer"
}

function set_version_defaults {
    # Purpose: Derive the standard upstream release URL from a version.
    # Arguments: rlwrap version string without the leading v.
    # Return value: Always succeeds.
    # Side effects: Updates RLWRAP_VERSION, SOURCE_URL, and maybe SOURCE_SHA256.
    typeset version=$1

    RLWRAP_VERSION=$version
    SOURCE_URL="https://github.com/hanslub42/rlwrap/releases/download/v${version}/rlwrap-${version}.tar.gz"

    if [[ $version == "$DEFAULT_RLWRAP_VERSION" ]]; then
        SOURCE_SHA256=$DEFAULT_SOURCE_SHA256
    else
        SOURCE_SHA256=
    fi
}

function parse_arguments {
    # Purpose: Parse command-line options into global settings.
    # Arguments: The original command-line arguments.
    # Return value: Always succeeds unless an option is invalid.
    # Side effects: Updates global installer settings, or exits for help/man.
    typeset opt
    typeset value

    while (( $# > 0 )); do
        opt=$1
        shift

        case "$opt" in
            --prefix)
                require_value "$opt" "${1:-}"
                INSTALL_PREFIX=$1
                shift
                ;;
            --prefix=*)
                INSTALL_PREFIX=${opt#*=}
                ;;
            --tools-prefix)
                require_value "$opt" "${1:-}"
                TOOLS_PREFIX=$1
                shift
                ;;
            --tools-prefix=*)
                TOOLS_PREFIX=${opt#*=}
                ;;
            --build-root)
                require_value "$opt" "${1:-}"
                BUILD_ROOT=$1
                shift
                ;;
            --build-root=*)
                BUILD_ROOT=${opt#*=}
                ;;
            --version)
                require_value "$opt" "${1:-}"
                set_version_defaults "$1"
                shift
                ;;
            --version=*)
                set_version_defaults "${opt#*=}"
                ;;
            --url)
                require_value "$opt" "${1:-}"
                SOURCE_URL=$1
                SOURCE_SHA256=
                shift
                ;;
            --url=*)
                SOURCE_URL=${opt#*=}
                SOURCE_SHA256=
                ;;
            --sha256)
                require_value "$opt" "${1:-}"
                SOURCE_SHA256=$1
                shift
                ;;
            --sha256=*)
                SOURCE_SHA256=${opt#*=}
                ;;
            --no-sha256)
                SOURCE_SHA256=
                ;;
            --jobs)
                require_value "$opt" "${1:-}"
                require_positive_integer "$opt" "$1"
                JOBS=$1
                shift
                ;;
            --jobs=*)
                value=${opt#*=}
                require_positive_integer --jobs "$value"
                JOBS=$value
                ;;
            --with-libptytty)
                LIBPTYTTY_MODE=with
                ;;
            --without-libptytty)
                LIBPTYTTY_MODE=without
                ;;
            --run-checks)
                RUN_CHECKS=yes
                ;;
            --keep-build)
                KEEP_BUILD=yes
                ;;
            --install-self)
                INSTALL_SELF=yes
                ;;
            --dry-run)
                DRY_RUN=yes
                ;;
            --force-non-smartos)
                FORCE_NON_SMARTOS=yes
                ;;
            --help|-h)
                usage
                exit 0
                ;;
            --man)
                manpage
                exit 0
                ;;
            --)
                break
                ;;
            *)
                die "unknown option: ${opt}"
                ;;
        esac
    done

    (( $# == 0 )) || die "unexpected operand: $1"
}

function normalize_settings {
    # Purpose: Remove trailing slashes and validate path-like settings.
    # Arguments: None.
    # Return value: Always succeeds unless a setting is unsafe.
    # Side effects: Updates global path settings.
    TOOLS_PREFIX=${TOOLS_PREFIX%/}
    INSTALL_PREFIX=${INSTALL_PREFIX%/}
    BUILD_ROOT=${BUILD_ROOT%/}

    [[ -n $TOOLS_PREFIX ]] || die "tools prefix must not be empty"
    [[ -n $INSTALL_PREFIX ]] || die "install prefix must not be empty"
    [[ -n $BUILD_ROOT ]] || die "build root must not be empty"
    [[ -n $RLWRAP_VERSION ]] || die "rlwrap version must not be empty"
    [[ $BUILD_ROOT != / ]] || die "build root must not be /"
    [[ $SOURCE_URL == http://* || $SOURCE_URL == https://* || $SOURCE_URL == file://* ]] \
        || die "source URL must start with http://, https://, or file://"
    if [[ -n $SOURCE_SHA256 ]]; then
        [[ ${#SOURCE_SHA256} == 64 && $SOURCE_SHA256 == +([[:xdigit:]]) ]] \
            || die "SHA-256 digest must be 64 hexadecimal characters"
    fi
}

function configure_path {
    # Purpose: Prefer SmartOS pkgsrc tools while retaining basic system paths.
    # Arguments: None.
    # Return value: Always succeeds.
    # Side effects: Exports PATH.
    PATH="${TOOLS_PREFIX}/bin:${TOOLS_PREFIX}/sbin:/usr/bin:/usr/sbin:/sbin"
    export PATH
}

function verify_target_zone {
    # Purpose: Guard against accidental installation on the wrong host type.
    # Arguments: None.
    # Return value: Succeeds when the host appears to be a SmartOS global zone.
    # Side effects: May exit through die.
    typeset os_name
    typeset zone_name

    [[ $DRY_RUN == yes ]] && return 0
    [[ $FORCE_NON_SMARTOS == yes ]] && return 0

    os_name=$(uname -s 2>/dev/null) || die "cannot run uname"
    [[ $os_name == SunOS ]] || die "this installer is for SmartOS/illumos; pass --force-non-smartos to override"

    if command_path zonename >/dev/null 2>&1; then
        zone_name=$(zonename 2>/dev/null) || die "cannot determine zonename"
        [[ $zone_name == global ]] || die "this installer is intended for the global zone, not zone ${zone_name}"
    else
        warn "zonename command not found; cannot prove this is the global zone"
    fi
}

function discover_tools {
    # Purpose: Find the external tools used by the installer.
    # Arguments: None.
    # Return value: Succeeds when required tools are found.
    # Side effects: Updates global tool path variables.
    if [[ $DRY_RUN == yes ]]; then
        FETCH_MODE=curl
        FETCH_TOOL="${TOOLS_PREFIX}/bin/curl"
        GZIP_TOOL="${TOOLS_PREFIX}/bin/gzip"
        TAR_TOOL="${TOOLS_PREFIX}/bin/gtar"
        MAKE_TOOL="${TOOLS_PREFIX}/bin/gmake"
        SHA256SUM_TOOL="${TOOLS_PREFIX}/bin/sha256sum"
        CC_TOOL="${CC:-${TOOLS_PREFIX}/bin/gcc}"
        CC=${CC:-$CC_TOOL}
        return 0
    fi

    if FETCH_TOOL=$(command_path curl); then
        FETCH_MODE=curl
    elif FETCH_TOOL=$(command_path wget); then
        FETCH_MODE=wget
    else
        die "need curl or wget under ${TOOLS_PREFIX}/bin or in PATH"
    fi

    GZIP_TOOL=$(command_path gzip) || die "need gzip under ${TOOLS_PREFIX}/bin or in PATH"

    if TAR_TOOL=$(command_path gtar); then
        :
    else
        TAR_TOOL=$(command_path tar) || die "need tar or gtar under ${TOOLS_PREFIX}/bin or in PATH"
    fi

    if MAKE_TOOL=$(command_path gmake); then
        :
    else
        MAKE_TOOL=$(command_path make) || die "need gmake or make under ${TOOLS_PREFIX}/bin or in PATH"
    fi

    if [[ -n ${CC:-} ]]; then
        CC_TOOL=$CC
    elif CC_TOOL=$(command_path gcc); then
        CC=$CC_TOOL
    elif CC_TOOL=$(command_path cc); then
        CC=$CC_TOOL
    else
        die "need gcc or another C compiler; set CC if it has a custom name"
    fi

    if [[ -n $SOURCE_SHA256 ]]; then
        SHA256SUM_TOOL=$(command_path sha256sum) || die "need sha256sum to verify the release tarball; use --no-sha256 only for deliberate testing"
    fi
}

function verify_build_inputs {
    # Purpose: Fail early for the SmartOS pkgsrc inputs rlwrap is known to need.
    # Arguments: None.
    # Return value: Succeeds when obvious inputs are present.
    # Side effects: May exit through die.
    [[ $DRY_RUN == yes ]] && return 0

    [[ -r "${TOOLS_PREFIX}/include/readline/readline.h" ]] \
        || die "GNU Readline headers not found at ${TOOLS_PREFIX}/include/readline/readline.h"

    if [[ ! -r "${TOOLS_PREFIX}/lib/libreadline.so" && ! -r "${TOOLS_PREFIX}/lib/libreadline.a" ]]; then
        die "GNU Readline library not found under ${TOOLS_PREFIX}/lib"
    fi

    if [[ ! -r "${TOOLS_PREFIX}/lib/libncurses.so" && \
          ! -r "${TOOLS_PREFIX}/lib/libcurses.so" && \
          ! -r "${TOOLS_PREFIX}/lib/libtinfo.so" && \
          ! -r "${TOOLS_PREFIX}/lib/libtinfow.so" && \
          ! -r "${TOOLS_PREFIX}/lib/libtermcap.so" ]]; then
        warn "no terminal library was found under ${TOOLS_PREFIX}/lib; configure may still find a system curses library"
    fi
}

function run {
    # Purpose: Run a command with progress logging and dry-run support.
    # Arguments: Command and arguments.
    # Return value: The command's exit status, or 0 in dry-run mode.
    # Side effects: Executes commands unless DRY_RUN is yes.
    print -r -- "+ $*"
    [[ $DRY_RUN == yes ]] && return 0
    "$@"
}

function fetch_source {
    # Purpose: Download the configured rlwrap source tarball.
    # Arguments: Archive path to create.
    # Return value: Succeeds when the archive is present.
    # Side effects: Creates the build root and writes the archive file.
    typeset archive=$1

    run mkdir -p "$BUILD_ROOT" || die "cannot create build root ${BUILD_ROOT}"

    notice "Downloading ${SOURCE_URL}"
    case "$FETCH_MODE" in
        curl)
            run "$FETCH_TOOL" -fL -o "$archive" "$SOURCE_URL" || die "download failed"
            ;;
        wget)
            run "$FETCH_TOOL" -O "$archive" "$SOURCE_URL" || die "download failed"
            ;;
        *)
            die "internal error: unknown fetch mode ${FETCH_MODE}"
            ;;
    esac
}

function verify_source_checksum {
    # Purpose: Compare the archive checksum with the expected digest.
    # Arguments: Archive path to verify.
    # Return value: Succeeds when no digest is configured or the digest matches.
    # Side effects: Reads the archive file and may exit through die.
    typeset archive=$1
    typeset line
    typeset actual

    if [[ -z $SOURCE_SHA256 ]]; then
        warn "source checksum verification is disabled"
        return 0
    fi

    [[ $DRY_RUN == yes ]] && return 0

    line=$("$SHA256SUM_TOOL" "$archive") || die "sha256sum failed for ${archive}"
    actual=${line%%[[:space:]]*}
    [[ $actual == "$SOURCE_SHA256" ]] \
        || die "checksum mismatch for ${archive}: expected ${SOURCE_SHA256}, got ${actual}"

    notice "Verified SHA-256 ${actual}"
}

function extract_source {
    # Purpose: Extract the source tarball into a predictable source directory.
    # Arguments: Archive path and source directory path.
    # Return value: Succeeds when the source directory exists.
    # Side effects: Removes any old source directory for this version.
    typeset archive=$1
    typeset source_dir=$2

    if [[ -d $source_dir ]]; then
        notice "Removing previous source directory ${source_dir}"
        run rm -rf "$source_dir" || die "cannot remove ${source_dir}"
    fi

    notice "Extracting source into ${BUILD_ROOT}"
    if [[ $DRY_RUN == yes ]]; then
        print -r -- "+ ${GZIP_TOOL} -dc ${archive} | (cd ${BUILD_ROOT} && ${TAR_TOOL} -xf -)"
        return 0
    fi

    if ! "$GZIP_TOOL" -dc "$archive" | (cd "$BUILD_ROOT" && "$TAR_TOOL" -xf -); then
        die "source extraction failed"
    fi

    [[ -d $source_dir ]] || die "expected source directory ${source_dir} was not created"
}

function export_build_environment {
    # Purpose: Point configure at the SmartOS tools prefix.
    # Arguments: None.
    # Return value: Always succeeds.
    # Side effects: Exports compiler and linker environment variables.
    CPPFLAGS="${CPPFLAGS:+$CPPFLAGS }-I${TOOLS_PREFIX}/include"
    LDFLAGS="${LDFLAGS:+$LDFLAGS }-L${TOOLS_PREFIX}/lib -Wl,-R,${TOOLS_PREFIX}/lib"
    PKG_CONFIG_PATH="${TOOLS_PREFIX}/lib/pkgconfig:${TOOLS_PREFIX}/share/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"

    export CC CPPFLAGS CFLAGS LDFLAGS LIBS PKG_CONFIG_PATH
}

function configure_source {
    # Purpose: Run rlwrap's configure script.
    # Arguments: Source directory.
    # Return value: Succeeds when configure succeeds.
    # Side effects: Writes configure output and generated build files.
    typeset source_dir=$1
    typeset libptytty_arg

    case "$LIBPTYTTY_MODE" in
        with) libptytty_arg='--with-libptytty' ;;
        without) libptytty_arg='--without-libptytty' ;;
        *) die "internal error: bad libptytty mode ${LIBPTYTTY_MODE}" ;;
    esac

    notice "Configuring rlwrap ${RLWRAP_VERSION}"
    if [[ $DRY_RUN == yes ]]; then
        print -r -- "+ cd ${source_dir}"
        print -r -- "+ ./configure --prefix=${INSTALL_PREFIX} ${libptytty_arg}"
        return 0
    fi

    cd "$source_dir" || die "cannot enter ${source_dir}"
    [[ -x ./configure ]] || die "configure script is missing or not executable in ${source_dir}"
    ./configure "--prefix=${INSTALL_PREFIX}" "$libptytty_arg" || die "configure failed"
}

function build_source {
    # Purpose: Compile rlwrap.
    # Arguments: None; configure_source has already changed into the source dir.
    # Return value: Succeeds when make succeeds.
    # Side effects: Writes build artifacts into the source tree.
    notice "Building rlwrap"
    run "$MAKE_TOOL" -j "$JOBS" || die "build failed"

    if [[ $RUN_CHECKS == yes ]]; then
        notice "Running rlwrap checks"
        run "$MAKE_TOOL" check || die "make check failed"
    fi
}

function install_source {
    # Purpose: Install rlwrap into the configured prefix.
    # Arguments: None; build_source has already built in the source dir.
    # Return value: Succeeds when make install succeeds.
    # Side effects: Writes files under INSTALL_PREFIX.
    notice "Installing rlwrap into ${INSTALL_PREFIX}"
    run "$MAKE_TOOL" install || die "make install failed"
}

function install_installer_manpage {
    # Purpose: Install this script's manual page under the target prefix.
    # Arguments: None.
    # Return value: Succeeds when the manual page is written.
    # Side effects: Writes PREFIX/man/man8/SCRIPT_NAME.8.
    typeset man_dir="${INSTALL_PREFIX}/man/man8"
    typeset man_file="${man_dir}/${SCRIPT_NAME}.8"

    notice "Installing installer manual page ${man_file}"
    run mkdir -p "$man_dir" || die "cannot create ${man_dir}"

    if [[ $DRY_RUN == yes ]]; then
        print -r -- "+ write ${man_file}"
        return 0
    fi

    manpage >"$man_file" || die "cannot write ${man_file}"
    chmod 0644 "$man_file" || die "cannot chmod ${man_file}"
}

function install_installer_script {
    # Purpose: Optionally copy this installer into the target prefix.
    # Arguments: None.
    # Return value: Succeeds when the copy succeeds or the option is disabled.
    # Side effects: Writes PREFIX/sbin/SCRIPT_NAME when INSTALL_SELF is yes.
    typeset script_dir="${INSTALL_PREFIX}/sbin"
    typeset script_file="${script_dir}/${SCRIPT_NAME}"

    [[ $INSTALL_SELF == yes ]] || return 0

    notice "Installing this installer as ${script_file}"
    run mkdir -p "$script_dir" || die "cannot create ${script_dir}"
    run cp "$SCRIPT_PATH" "$script_file" || die "cannot copy installer to ${script_file}"
    run chmod 0755 "$script_file" || die "cannot chmod ${script_file}"
}

function smoke_test {
    # Purpose: Confirm that the installed rlwrap executable starts.
    # Arguments: None.
    # Return value: Succeeds when rlwrap --version succeeds.
    # Side effects: Executes the installed rlwrap.
    typeset rlwrap_bin="${INSTALL_PREFIX}/bin/rlwrap"

    [[ $DRY_RUN == yes ]] && return 0
    [[ -x $rlwrap_bin ]] || die "installed rlwrap not found at ${rlwrap_bin}"

    notice "Smoke-testing ${rlwrap_bin}"
    "$rlwrap_bin" --version || die "installed rlwrap did not run"
}

function cleanup_build {
    # Purpose: Remove build artifacts unless the user asked to keep them.
    # Arguments: Source directory path.
    # Return value: Always succeeds unless removal fails.
    # Side effects: May remove the extracted source tree.
    typeset source_dir=$1

    [[ $KEEP_BUILD == yes ]] && return 0
    [[ $DRY_RUN == yes ]] && return 0
    [[ -d $source_dir ]] || return 0

    notice "Cleaning build directory ${source_dir}"
    cd "$BUILD_ROOT" || die "cannot enter ${BUILD_ROOT} before cleanup"
    rm -rf "$source_dir" || die "cannot remove ${source_dir}"
}

function main {
    # Purpose: Coordinate argument parsing, build, install, and verification.
    # Arguments: Original command-line arguments.
    # Return value: Exits 0 on success.
    # Side effects: Downloads, builds, installs, and cleans up rlwrap.
    typeset archive
    typeset source_dir

    parse_arguments "$@"
    normalize_settings
    configure_path
    verify_target_zone
    discover_tools
    verify_build_inputs
    export_build_environment

    archive="${BUILD_ROOT}/rlwrap-${RLWRAP_VERSION}.tar.gz"
    source_dir="${BUILD_ROOT}/rlwrap-${RLWRAP_VERSION}"

    notice "Using tools prefix ${TOOLS_PREFIX}"
    notice "Using install prefix ${INSTALL_PREFIX}"
    notice "Using build root ${BUILD_ROOT}"

    fetch_source "$archive"
    verify_source_checksum "$archive"
    extract_source "$archive" "$source_dir"
    configure_source "$source_dir"
    build_source
    install_source
    install_installer_manpage
    install_installer_script
    smoke_test
    cleanup_build "$source_dir"

    notice "rlwrap ${RLWRAP_VERSION} installation complete"
}

main "$@"

# install-rlwrap-smartos.ksh ends here
