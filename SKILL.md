---
name: cloudberry-build
description: "How to configure, compile, run, and test Cloudberry Database (CBDB) for development. Use this skill whenever the user wants to build CBDB from source, set up a development cluster, run tests, or troubleshoot build issues. Also trigger when the user mentions: configure, make, compile, gpinitsystem, demo cluster, gpstart, gpstop, installcheck, unit test, or any Cloudberry/CBDB build-related task."
---

# Cloudberry Database: Build, Run & Test Guide

This skill covers the full developer workflow for Cloudberry Database — from configuring the build to running tests against a live cluster. **All commands assume you are running Claude from the Cloudberry project root directory.**

## Install Prefix Selection

When choosing `--prefix` for `./configure`, try the following paths **in order**. Use `mkdir -p` to test; if it fails (e.g., permission denied), try the next one:

```
INSTALL_PREFIX candidates (in priority order):
  1. /usr/local/cloudberry-db-devel
  2. ~/cbdb.bin
```

Throughout this document, `$INSTALL_PREFIX` refers to whichever path was successfully created.

## Quick Reference

| Step | Command |
|------|---------|
| Configure | `./configure --prefix=$INSTALL_PREFIX ...` |
| Build | `make -j$(nproc)` |
| Install | `make install` |
| Environment | `source $INSTALL_PREFIX/cloudberry-env.sh` |
| Create cluster | `make create-demo-cluster` |
| Start cluster | `source gpAux/gpdemo/gpdemo-env.sh && gpstart -a` |
| Stop cluster | `gpstop -a -M fast` |
| Run tests | `make installcheck` |

---

## Step 1: Configure

The project uses autoconf. Run `./configure` from the project root with the flags appropriate for development:

```bash
./configure --prefix=$INSTALL_PREFIX \
    --enable-debug \
    --enable-cassert \
    --enable-depend \
    --with-lz4 \
    --with-gssapi \
    --enable-orafce \
    --enable-ic-proxy \
    --enable-orca \
    --enable-gpcloud \
    --with-libxml \
    --with-ssl=openssl \
    --with-pam \
    --with-ldap \
    --with-python \
    --with-pythonsrc-ext
```

**Important**: `--prefix` must use an absolute path. Do NOT use unexpanded `$HOME` — it may not be expanded by configure and result in installing to a wrong location. Use the fully resolved path (e.g., `/usr/local/cloudberry-db-devel` or `/home/gpadmin/cbdb.bin`).

**Flag explanations:**
- `--enable-debug` — Include debug symbols (`-g`), essential for gdb debugging
- `--enable-cassert` — Turn on assertion checks; catches bugs early but slows runtime
- `--enable-depend` — Track header dependencies so incremental builds work correctly
- `--enable-orca` — Enable the ORCA query optimizer (on by default, but explicit is clearer)
- The `--with-*` flags enable optional features (XML, SSL, LZ4 compression, etc.)

**Optional flags** (add only if the dependencies are available):
- `--with-perl` — Build PL/Perl (requires libperl as a shared library; if `configure` reports "cannot build PL/Perl because libperl is not a shared library", drop this flag)
- `--enable-mapreduce` — Enable MapReduce support (requires `--with-perl`, so if Perl is unavailable, drop this too)

### Common configure issues

- **Missing library**: Install the `-devel` / `-dev` package. For example, `yum install lz4-devel` or `apt install liblz4-dev`.
- **"libperl is not a shared library"**: Your Perl was compiled without `-Duseshrplib`. Either rebuild Perl with shared lib support, or drop `--with-perl` and `--enable-mapreduce`.
- **Re-running configure after changes to `configure.ac`**: Run `autoconf` first to regenerate the configure script.
- **Switching between debug and release**: Do `make distclean` before reconfiguring to avoid stale object files.

---

## Step 2: Build

```bash
make -j$(nproc)
```

`-j$(nproc)` uses all CPU cores for parallel compilation. On a machine with 8 cores this cuts build time significantly.

**Incremental builds**: After modifying source files, just run `make -j$(nproc)` again — the `--enable-depend` flag ensures only changed files and their dependents rebuild.

**Building specific subdirectories**: If you only changed code in one area, you can build just that part:

```bash
# Example: rebuild just the backend
make -C src/backend -j$(nproc)

# Example: rebuild a contrib extension
make -C contrib/pg_stat_statements -j$(nproc)
```

---

## Step 3: Install

```bash
make install
```

This installs binaries, libraries, and headers to the `--prefix` directory (`$INSTALL_PREFIX`).

For contrib and gpcontrib extensions:

```bash
make -C contrib install
make -C gpcontrib install
```

---

## Step 4: Set Up Environment

Source the environment script so shell tools (`psql`, `gpstart`, etc.) are on your PATH:

```bash
source $INSTALL_PREFIX/cloudberry-env.sh
```

This sets `GPHOME`, `PATH`, `LD_LIBRARY_PATH`, and `PYTHONPATH`.

Add this to your `~/.bashrc` if you want it loaded automatically:

```bash
echo "source $INSTALL_PREFIX/cloudberry-env.sh" >> ~/.bashrc
```
<!-- comment: 不要将数据库相关的环境变量混入默认的环境变量，可能造成环境变量污染，系统可能需要同时运行多个数据库实例。建议将需要设置的环境变量添加到类似.cloudberry.env的文件中，在需要使用前，source这个文件来生效 -->

---

## Step 5: Create a Demo Cluster

The demo cluster creates a single-host cluster with a coordinator and several segments — perfect for development and testing.

**Pre-check**: `make create-demo-cluster` internally calls `gpinitsystem` which uses `ping` to verify the host. Make sure:
- `ping` is on your PATH (it's often in `/usr/sbin/`, which may not be in PATH by default — add `export PATH=$PATH:/usr/sbin` if needed)
- `ping` has the correct permissions (in containers, you may need `sudo chmod u+s /usr/sbin/ping` or `sudo setcap cap_net_raw+ep /usr/sbin/ping`)

```bash
make create-demo-cluster
```

This is equivalent to running the `gpdemo` script in `gpAux/gpdemo/`. The default configuration:
- 3 primary segments + 3 mirrors
- Ports starting from 7000
- Data stored in `gpAux/gpdemo/datadirs/`

**Customizing the demo cluster** (via environment variables before running):

```bash
export PORT_BASE=7000                    # Base port number
export NUM_PRIMARY_MIRROR_PAIRS=3        # Number of segment pairs
export WITH_MIRRORS=true                 # Enable/disable mirrors
export WITH_STANDBY=true                 # Enable standby coordinator
```

**Single-node mode** (no segments, just coordinator — faster for simple testing):

```bash
NUM_PRIMARY_MIRROR_PAIRS=0 make create-demo-cluster
```

After creation, source the demo environment:

```bash
source gpAux/gpdemo/gpdemo-env.sh
```

This sets `COORDINATOR_DATA_DIRECTORY` and `PGPORT` so tools know where to connect.

---

## Step 6: Start / Stop / Check the Cluster

```bash
# Start all segments
gpstart -a

# Check cluster status
gpstate

# Connect to the database
psql -d postgres

# Stop gracefully
gpstop -a

# Fast stop (skip client disconnect wait)
gpstop -a -M fast

# Immediate stop (emergency only — risk of data corruption)
gpstop -a -M immediate
```

---

## Step 7: Run Tests

### Regression tests (requires a running cluster)

```bash
# Standard regression suite
make installcheck

# Full test world (all test suites)
make installcheck-world
```

### Unit tests (no running cluster needed)

```bash
make CFLAGS=-DUNITTEST unittest-check
```

### Isolation tests

```bash
make -C src/test/isolation2 installcheck
```

### Specific test files

```bash
# Run a single regression test
make -C src/test/regress installcheck EXTRA_TESTS=your_test_name
```

### Interpreting test results

- **Success**: Output shows "All N tests passed"
- **Failure**: Look at `regression.diffs` for the diff between expected and actual output
- The file `regression.out` contains the raw test output

---

## Destroy and Recreate the Cluster

When you need a fresh cluster (e.g., catalog schema changes):

```bash
# Destroy the existing demo cluster
make destroy-demo-cluster

# Recreate from scratch
make create-demo-cluster
source gpAux/gpdemo/gpdemo-env.sh
```

---

## Useful Management Commands

| Command | What it does |
|---------|-------------|
| `gpstate` | Show cluster status |
| `gpstate -s` | Show segment details |
| `gpconfig -s <guc>` | Show a GUC parameter value |
| `gpconfig -c <guc> -v <value>` | Set a GUC parameter |
| `gpstop -u` | Reload config without restart |
| `gpcheckcat -p <port>` | Check catalog consistency |
| `gpssh -f hostfile -e 'cmd'` | Run command on all hosts |

---

## Full Rebuild from Scratch

When you need a completely clean build (e.g., after pulling major changes):

```bash
# Stop cluster if running
source $INSTALL_PREFIX/cloudberry-env.sh
source gpAux/gpdemo/gpdemo-env.sh
gpstop -a -M fast 2>/dev/null

# Destroy demo cluster
make destroy-demo-cluster 2>/dev/null

# Clean everything
make distclean

# Reconfigure, build, install, create cluster
./configure --prefix=$INSTALL_PREFIX \
    --enable-debug --enable-cassert --enable-depend \
    --with-lz4 --with-gssapi \
    --enable-orafce --enable-ic-proxy --enable-orca \
    --enable-gpcloud --with-libxml --with-ssl=openssl \
    --with-pam --with-ldap --with-python --with-pythonsrc-ext

make -j$(nproc)
make install
source $INSTALL_PREFIX/cloudberry-env.sh
make create-demo-cluster
source gpAux/gpdemo/gpdemo-env.sh
gpstart -a
gpstate
```

---

## Key Paths

| Path | Description |
|------|-------------|
| `.` (project root) | Source tree (Claude's working directory) |
| `$INSTALL_PREFIX` | Install directory (see prefix selection above) |
| `$INSTALL_PREFIX/cloudberry-env.sh` | Environment setup |
| `gpAux/gpdemo/gpdemo-env.sh` | Demo cluster environment |
| `gpAux/gpdemo/datadirs/` | Demo cluster data files |
| `gpMgmt/doc/gpconfigs/` | Config file templates |
| `gpMgmt/bin/` | Management tools |
