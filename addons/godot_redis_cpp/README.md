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

> **Note for Windows Users:** This is a Bash script. You can run it using Git Bash (which comes with Git for Windows) or the Windows Subsystem for Linux (WSL). Alternatively, you can inspect the script and perform the steps (`mklink` or file copies) manually.

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
scons platform=linux # Or your target platform
```
The compiled library (e.g., `libgodot-redis.so`) will appear in the `addons/godot_redis_cpp/bin/` directory.

## Activation in Godot

1. Open your Godot project.
2. Go to **Project -> Project Settings -> Plugins**.
3. Find **"Godot Redis"** in the list and set its status to **Active**.

This will automatically add the `NetworkManager` and its controller modules to your project's Autoloads, making them ready to use.
