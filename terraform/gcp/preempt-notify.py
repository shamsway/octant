import paho.mqtt.client as mqtt
import logging

# Configure logging
logging.basicConfig(level=logging.DEBUG)

# MQTT broker details
broker_address = "mqtt.service.consul"
broker_port = 1883
topic = "gcp/vm/preempted"

# Callback function for connection status
def on_connect(client, userdata, flags, rc):
    logging.debug(f"on_connect called with reason_code: {rc}")
    if rc == 0:
        logging.info("Connected to MQTT broker")
    else:
        logging.error(f"Failed to connect, return code: {rc}")

# Callback function for publish status
def on_publish(client, userdata, mid):
    logging.debug(f"Message published with mid: {mid}")

# Create an MQTT client instance
client = mqtt.Client()

# Set the callback functions
client.on_connect = on_connect
client.on_publish = on_publish

# Enable logging
client.enable_logger()

# Connect to the MQTT broker
logging.debug(f"Connecting to MQTT broker at {broker_address}:{broker_port}")
try:
    client.connect(broker_address, broker_port, keepalive=60)
except Exception as e:
    logging.error(f"Error connecting to MQTT broker: {str(e)}")
    exit(1)

# Publish a shutdown message
logging.info(f"Publishing shutdown message to topic: {topic}")
result, mid = client.publish(topic, "shutdown", qos=1)
if result != mqtt.MQTT_ERR_SUCCESS:
    logging.error(f"Failed to publish shutdown message. Error: {result}")

# Disconnect from the MQTT broker
logging.info("Disconnecting from MQTT broker")
client.disconnect()