# Godot Redis

A high-performance GDExtension C++ client for Redis.

## Overview

This addon provides a modular, WebSocket-based networking framework for creating multiplayer game backends and admin dashboards directly in Godot.
MIT Licensed.

## System Requirements

Before compiling, ensure you have the following installed:
- Godot Engine 4.4 or higher
- A C++ compiler (g++, clang++, or MSVC)
- Python 3.8+ and SCons 4.0+
- Git

Additionally, this addon requires the following development libraries to be installed on your system.

**On Debian/Ubuntu:**
```bash
sudo apt-get update
sudo apt-get install libhiredis-dev libuv1-dev libssl-dev
```
**On Windows:**
- **Visual Studio 2022** (or newer) with the "Desktop development with C++" workload.
- **vcpkg (C++ Package Manager):** Follow the [official vcpkg guide](https://vcpkg.io/en/getting-started.html) to install it.
- **Strawberry Perl:** Download and install from [strawberryperl.com](https://strawberryperl.com/). Ensure it's added to your system's PATH.
- **NASM Assembler:** Download and install the `win64` installer from the [official NASM website](https://www.nasm.us/). Ensure it's added to your system's PATH.

**On other systems, please install the equivalent packages.**

## Setup and Compilation

Follow these steps to set up and compile the addon.

### 1. Initialize Submodules

This project uses Git submodules for its core dependencies. After cloning the main repository, run this command from its root to download `godot-cpp` and `redis-plus-plus`:

```bash
git submodule update --init --recursive
```

### 2. Configure Dependencies (Required)

This addon requires some manual configuration of its dependencies. A setup script is provided to automate this process.

From the root of the **addon directory** (`addons/godot_redis_cpp/`), run the setup script:

```bash
# Navigate to the addon directory first
cd addons/godot_redis_cpp

# Run the script
./setup_dependencies.sh
```

This will create the necessary symbolic links and configuration files inside the `redis-plus-plus` submodule.

> **Note for Windows Users:** This is a Bash script that create sym-links to the required dependencies for Linux. You can copy this files manually for the Windows system.

#### On Windows (Required)

You must use `vcpkg` to install the C++ libraries required by this addon.

First, set the `VCPKG_ROOT` environment variable to point to your `vcpkg` installation directory.

Then, open a **Developer Command Prompt for VS** and run the following commands to install the necessary dependencies:

```bash
# Install the required libraries for the x64-windows target
vcpkg install hiredis:x64-windows libuv:x64-windows openssl:x64-windows
```

> **Note:** The OpenSSL installation may take a significant amount of time. The successful installation of Perl and NASM is critical for this step to succeed.


### 3. Generate Godot-CPP Bindings

Navigate into the `godot-cpp` submodule and generate the C++ bindings for your version of Godot.

```bash
cd addons/godot_redis_cpp/godot-cpp
scons platform=linux generate_bindings=yes custom_api_file=../extension_api.json # Replace 'linux' with 'windows' or 'macos'
cd ..
```

### 4. Compile the Addon

Now you can compile the GDExtension library.

```bash
# On Linux:
scons platform=linux

# On Windows (from a Developer Command Prompt for VS):
scons platform=windows
```

The compiled library (e.g., `libgodot-redis.dll` or `libgodot-redis.so`) will appear in the `addons/godot_redis_cpp/bin/` directory.

On windows you have to copy `hiredis.dll` from the vcpkg to the folder where `libgodot-redis.dll` is located

## Activation in Godot

1. Open your Godot project.
2. Go to **Project -> Project Settings -> Plugins**.
3. Find **"Godot Redis"** in the list and set its status to **Active**.
