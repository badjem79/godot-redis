// src/register_types.h
#ifndef REGISTER_TYPES_H
#define REGISTER_TYPES_H
#include <godot_cpp/core/class_db.hpp>
using namespace godot;
void initialize_redis_module(ModuleInitializationLevel p_level);
void uninitialize_redis_module(ModuleInitializationLevel p_level);
#endif // REGISTER_TYPES_H
