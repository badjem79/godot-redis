extends Control

@onready var port_label = $Panel/Label2
@onready var redis_status_label = $Panel/Label4

@onready var backend_server = %BackendServer

@onready var redis_client = %RedisClient

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	port_label.text = str(backend_server.WEB_PORT)


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta: float) -> void:
	if redis_client.is_connected:
		redis_status_label.text = "Connected"
	else:
		redis_status_label.text = "Not Connected"
