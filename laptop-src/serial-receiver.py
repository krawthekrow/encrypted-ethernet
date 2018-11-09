'''Automatically find USB Serial Port
jodalyst 9/2017
'''

import serial.tools.list_ports
import sys
import time
from time import sleep

def get_usb_port():
	usb_port = list(serial.tools.list_ports.grep('USB-Serial Controller'))
	if len(usb_port) == 1:
		print('Automatically found USB-Serial Controller: {}'.format(usb_port[0].description))
		return usb_port[0].device
	else:
		ports = list(serial.tools.list_ports.comports())
		port_dict = {i:[ports[i],ports[i].vid] for i in range(len(ports))}
		usb_id = None
		for p in port_dict:
			print('{}:   {} (Vendor ID: {})'.format(p,port_dict[p][0],port_dict[p][1]))
			if port_dict[p][1]==1027:
				usb_id = p
		if usb_id == None:
			return None
		else:
			print('USB-Serial Controller: Device {}'.format(p))
			return port_dict[usb_id][0].device

serial_port = get_usb_port()
if serial_port is None:
	raise Exception('USB-Serial Controller Not Found')

with serial.Serial(port = serial_port, 
		baudrate=115200, 
		parity=serial.PARITY_NONE, 
		stopbits=serial.STOPBITS_ONE, 
		bytesize=serial.EIGHTBITS,
		timeout=0) as ser, open('dump.log', 'wb') as f:

	print(ser)
	print('Serial Connected!')

	if ser.isOpen():
		print(ser.name + ' is open...')

	ser.write(bytes.fromhex('00001122'))
	while True:
		data = ser.read(128)
		if len(data) > 0:
			print('received %d bits' % len(data))
			f.write(data)
			f.flush()
