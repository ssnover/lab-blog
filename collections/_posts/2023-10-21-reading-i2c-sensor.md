---
layout: post
title: "Reading an I2C Sensor with Arduino"
date: 2023-10-21
projects: [tutorial]
---

If you've developed a few Arduino projects, you've probably learned to use the Arduino library's I2C driver `Wire` or perhaps also it's SPI driver `SPI`. These two protocols are very commonly used in embedded systems for communication between a microcontroller and a secondary chip like a sensor. The Arduino IDE has made downloading libraries to use in your project easier than ever, but what happens when you can't find a library for your sensor? Or perhaps there's a bug in the library you're using and it doesn't quite work properly?

Today I'll be covering some cut content from my course on [IoT with Arduino](https://shanesnover.com/iot-arduino-course/intro.html) in order to expand from the code there into writing a lower-level driver in the event you can't find a suitable library. Along the way I'll be explaining (or deferring to an explanation of) how the I2C protocol works and we'll be using the Arduino library's `Wire` object to write the driver rather than going even further. This allows you to leverage the code you write on anything Arduino runs on and gives you a good foundation if you ever have to dig deeper on a platform where you can't or don't want to use Arduino.

I'll also be explaining some elements of reading a datasheet and performing bitwise operations that are the bread and butter of working with constrained embedded systems.

## Overview of the Sensor
In following with the course, the sensor we'll be examining today is the AHT20. It is capable of measuring the temperature and humidity of the environment and those measurements can be triggered and read back over the I2C protocol. This sensor is pretty widely available on breakout boards from the usual suspects.

As we walk through this, I'll be referencing the datasheet (or product manual) of the sensor pretty heavily. Specifically, sections 5 and 6. You can find the [full datasheet here](/assets/pdf/aht20-product-manual.pdf).

But before we go in too deep, a quick aside about I2C.

### I2C Protocol
I2C is a two-wire protocol (not counting ground). Many breakout boards sold can be hooked up to an Arduino easily with just power, ground, and two signal wires: `SDA` and `SCL`. Unlike Serial UART where you need to set the communication frequency "out-of-band", I2C utilizes a wire just for the clock signal. This clock signal is controlled by a device referred to in the protocol as the "master" device and additional devices connected to it are "I2C slave" devices. I prefer "I2C controller" and "I2C device" respectively, and will use those for the rest of this post.

Having a single controller and multiple devices is one major advantage over Serial UART where only two devices can be connected. It also presents an obvious question: if you have two I2C devices, how does each device know when a request is intended to go to itself or to another device. Luckily, this is conveniently handled with addresses, much like IP addresses on a home network.

So in order to send a write command, the controller begins to toggle the clock signal at the desired frequency and then raises or lowers the `SDA` (data) signal to first send the device address, and then the payload of the message which is one or more bytes. In order to read from a device, the controller first writes the address, and then continues to toggle the clock line to indicate to the device that it wants more data. The device then drives the data line.

In order for the device to know the difference between a write with a payload of `[0x00, 0x00, 0x00]`, the address is slightly modified. I2C device addresses are 7 bits, but are sent over the wire as a single byte, with the remaining bit indicating whether the command is a read or a write.

For more details on the I2C protocol, check out this great page from Sparkfun: https://learn.sparkfun.com/tutorials/i2c/all.

## Initializing the Sensor
I'm going to hop back and forth between quoting the datasheet and implementing our code here for engagement's sake. To begin, here's a basic Arduino sketch that I'll be building from:

```cpp
#include "Arduino.h"

void setup() {
    // Initialization
    const int LED_PIN = 13;
    pinMode(LED_PIN, OUTPUT);
    bool led_state = false;

    Serial.begin(115200);
    Serial.println();
    Serial.println("info: booting");

    // Main loop
    while (true) {
        digitalWrite(LED_PIN, led_state);
        led_state = !led_state;
        delay(5000);
    }
}

void loop() {}
```

Now, if we go take a look at the datasheet and go to Section 5, we'll find some key parameters that we need to talk to the chip. This section has the first detail you need when talking an I2C device: the I2C address. For this chip it's `0x38` and unlike a number of breakout boards there doesn't seem to be any pins available to change that address. If you're trying to read from more than one of these boards you'll need multiple buses or an adapter to sit in front of each remaining sensor.

Section 5.4 describes the process for reading data from the sensor. The very first step is to send an initialization command and then verify that it's status byte has bit 3 set. It's not necessary to do this every time, but it's fair to assume that if your code is booting then the microcontroller, and also the sensor, have just powered up and initialization is necessary. This won't be true during development when you're flashing new code all the time, but it's no harm.

Let's start on a C++ class for the sensor handle. You can put this in the same source file as your Arduino sketch or in a separate file if you want to re-use it in other projects conveniently.

```cpp
#include "Wire.h"
#include <stdint.h>

class AHT20Handle {
public:
	static AHT20Handle connect();
	~AHT20Handle() = default;
private:
    AHT20Handle() = default;
	static constexpr uint8_t ADDRESS = 0x38;

	bool is_ready();
};

AHT20Handle AHT20Handle::connect() {
	AHT20Handle handle;
	delay(40); // delay to allow sensor to initialize on boot
	
	static const uint8_t INIT_SEQUENCE[3] = {0xBE, 0x08, 0x00};
	Wire.beginTransmission(AHT20Handle::ADDRESS);
	Wire.write(&INIT_SEQUENCE, 3);
	Wire.endTransmission();

	delay(10); // delay to allow sensor to calibrate

	while (!handle.is_ready()) {
		delay(10); // continuously delay until the sensor is ready
	}

	return handle;
}

bool AHT20Handle::is_ready() {
	Wire.requestFrom(AHT20Handle::ADDRESS, 1);
	while (!Wire.available()) {
		delay(1);
	}
	uint8_t status = Wire.read();
	return status & (1u << 3);
}

```


That was a lot of code to dump so we'll break it up into sections. First looking at all of the C++ class definition boilerplate:

```cpp
class AHT20Handle {
public:
	static AHT20Handle connect();
	~AHT20Handle() = default;
private:
    AHT20Handle() = default;
	static constexpr uint8_t ADDRESS = 0x38;

	bool is_ready();
};
```

Since we've got the I2C address, this seems like an appropriate place to write down that information in a constant that's privately available to the class.

For the initialization, I actually made the constructor private which means that it's not possible for a function outside of the class definition to construct one. This makes it possible to guard the ownership of the `AHT20Handle` behind a function that does the connection, initialization, and waits until it's ready. If user code has an instance of this class, you know for sure that all of those steps have happened. So instead, you have to create one with like this: 

```cpp
auto aht20 = AHT20Handle::connect();
```

Finally, I just marked the default constructor and destructor as default. This class doesn't actually hold onto any data so that's fine.

Next, we check out the `is_ready` function:

```cpp
bool AHT20Handle::is_ready() {
	Wire.requestFrom(AHT20Handle::ADDRESS, 1);
	while (!Wire.available()) {
		delay(1);
	}
	uint8_t status = Wire.read();
	return status & (1u << 3);
}
```

This code is responsible for reading the sensor's status word and checking if bit 3 is set. We use the Arduino's library to read a single byte from the sensor address and wait for that byte to come back. Once we have it, we need to do some bitwise logic, which is that last line.

If you haven't done bitwise logic in C/C++ before, that line of code probably looks a little bit arcane. What's happening here is we have a single byte of data from the sensor, which I'll represent like this: `0bxxxxSxxx`. We don't care what most of the bits actually are so I've marked them as `x` however we do care about bit 3, which I've marked with `S`. We don't want those other bits to influence our result so we need to clear them. In bitwise logic, anything logically ANDed with 0 will be 0, so we can consider that to be a clear operation. On the other hand, anything logically ANDed with 1, will be whatever it originally is. So in order to isolate the bit we care about, we can bitwise AND with `0b00001000`. That constant is easy to mis-type and at a glance it's not clear which bit is of interest. So a shorthand way to represent that information is with a bit-shift: `(1u << 3) == 0b00001000`. 

So, after all that, we get `0b0000S000`. If that bit is high, when it's casted to a boolean it will be `true`, and `false` otherwise. 

```cpp
AHT20Handle AHT20Handle::connect() {
	AHT20Handle handle;
	delay(40); // delay to allow sensor to initialize on boot
	
	static const uint8_t INIT_SEQUENCE[3] = {0xBE, 0x08, 0x00};
	Wire.beginTransmission(AHT20Handle::ADDRESS);
	Wire.write(&INIT_SEQUENCE, 3);
	Wire.endTransmission();

	delay(10); // delay to allow sensor to calibrate

	while (!handle.is_ready()) {
		delay(10); // continuously delay until the sensor is ready
	}

	return handle;
}
```

Moving onto the last piece of the initialization code, we have the `connect` method itself. With the Arduino I2C library we need to send the sequence `0xBE 0x08 0x00` to trigger the device to start calibration. 

I added some delays of tens of milliseconds in some places which would not be very appropriate for code that's being called frequently at runtime, but it can be okay during initialization. If you develop a system where startup time is important, you might consider breaking this function up so that you can do other work instead of waiting. The other thing I'm assuming here is that if you can't initialize the sensor then the program can stop. It might be important to error.

Once we've finished waiting the appropriate amount of time following calibration. We use the `is_ready` function to verify it. Once that's done we return the instance of the sensor handle. Now we can read some data!

## Reading Temperature Data
Next we're going to tackle reading the data from the sensor. Going back to the datasheet. It describes the process as: send a command to trigger a measurement with the sequence `0xAC 0x33 0x00`, wait 80 milliseconds, then read a status byte. The status byte will indicate if you can proceed to read the remaining data.

Let's add two functions to our class: `read_temperature` which is public, and `read_temperature_data` which is private:

```cpp
class AHT20Handle {
public:
	float read_temperature();

private:
	uint32_t read_temperature_data();
}
```

The public method will be what the user code uses. It will utilize the private method to read the data and then convert it into the float data. The data from the sensor is 20 bits (based on the figure) so our next fixed-size datatype up from that is a `uint32_t` which can be used to store the raw format of the data.

We'll examine the implementation of the private method first.

```cpp
uint32_t AHT20Handle::read_temperature_data() {
	static const uint8_t TRIGGER_MEASUREMENT_CMD[3] = {0xAC, 0x33, 0x00}; 
	Wire.beginTransmission(AHT20Handle::ADDRESS);
	Wire.write(&TRIGGER_MEASUREMENT_CMD, 3);
	Wire.endTransmission();

	delay(80); // delay to allow the measurement to occur

	bool data_available = false;
	while (!data_available) {
		Wire.requestFrom(AHT20Handle::ADDRESS, 1);
		while (!Wire.available()) {
			delay(1);
		}
		uint8_t status = Wire.read();
		data_available = status & (1u << 7);
	}

	uint8_t data_buffer[7] = {0, 0, 0, 0, 0, 0, 0};
	Wire.requestFrom(AHT20Handle::ADDRESS, 7);
	for (auto bytes_read = 0u; bytes_read < 7; ++bytes_read) {
		if (Wire.available()) {
			data_buffer[bytes_read] = Wire.read();
		} else {
			delay(1);
		}
	}

	// The temperature data exists in bytes 3, 4, and 5 of the reading
	uint32_t data = data_buffer[3] & 0b00001111;
	data = data << 8;
	data |= data_buffer[4];
	data = data << 8;
	data |= data_buffer[5];

	return data;
}
```

The first two sections are concerned with sending the trigger measurement command over I2C, waiting, and then attempting to read and check the status byte. This time the datasheet instructs us to check bit 7, so we do that with `status & (1u << 7)`. Once we know the data is ready, we can read the larger data packet.

The full sequence is shown in the figure in the bottom right of the page. The first byte is again the status byte, followed by the two bytes of humidity data, a byte of humidity data and temperature data, two bytes of temperature data, and finally an error checking CRC byte at the end. We're going to ignore that last byte for simplicity, but it's helpful if you are worried about data corruption during communication due to electrical noise.

The main question is how to assemble our 20 bits of data from the payload. Generally, data is encoded on a wire in big endian format. That means the most significant bit will be sent first and the least significant bit will be sent last. If the datasheet doesn't explicitly say otherwise, it's a good initial assumption. If it's not correct and you've decoded it backwards, you'd see very large swings in the temperature measurement so that's a good double check.

We're going to do more bit-shifting logic in order to assemble the 20-bits into our variable. We'll initialize it first by reading bits 19 down to 16 into bits 3 down to 0 of the variable. We can then shift left by 8, which moves those bits into positions 11 down to 8. By logically ORing the next byte of data it now puts into the lowest 8 bits. With one more shift left by 8, all of previously read bits are in the correct position and we can OR in the last byte of data.

## Converting to Celsius

Of course, if we're reading temperature data it's not very convenient to work with this integer. What units of measurement is this data even in? It's certainly not in degrees Celsius.

This data is in a specific scale that's based on the resolution of the data and the range of the sensor. For binary data it doesn't make sense to represent negative data, so `0x00000` represents the minimum value that the sensor can measure. Similarly, the sensor has a maximum value it can measure, and in order to use the full range of it's resolution this usually maps to the maximum value of `0xFFFFF`. 

The formula for converting to degrees is linear in this case, but that doesn't necessarily have to be the case. The actual quantity being measured may be in different units than you'd be accustomed to based on what is convenient for the MEMS sensor, so you should always check. Let's turn to Section 6.2 of the datasheet to see how it works for this sensor.

The formula shown describes dividing the measurement data by a value of 2^20 which represents the maximum resolution of the sensor. Then multiplying by 200 (the difference between the maximum and minimum values). Finally, subtract by 50 (-50 is the minimum value that can be measured). Because our measurement is only 20 bits, dividing it by 2^20 will always be bound between 0 and 1, so it's important not to treat these as integers in this operation (which will always be 0).

With all that in mind, let's implement the public `read_temperature` function.

```cpp
float AHT20Handle::read_temperature() {
	uint32_t raw_data = this->read_temperature_data();
	float ratio = static_cast<float>(raw_data) / (1ul << 20);
	return (ratio * 200.0) - 50.0;
}
```

## Plugging It Back In
We've been off implementing the class definition for this sensor for some time, so let's bring it all back and use it in the Arduino sketch I showed at the beginning:

```cpp
void setup() {
    // Initialization
    const int LED_PIN = 13;
    pinMode(LED_PIN, OUTPUT);
    bool led_state = false;

    Serial.begin(115200);
    Serial.println();
    Serial.println("info: booting");

	AHT20Handle aht20 = AHT20Handle::connect();

    // Main loop
    while (true) {
	    float temperature = aht20.read_temperature();
	    Serial.print("data: ");
	    Serial.println(temperature);
	    
        digitalWrite(LED_PIN, led_state);
        led_state = !led_state;
        delay(5000);
    }
}
```

With all of the code in the class hiding the complexity, the usage in the sketch code is trivial! Initialize the instance by calling `connect()`, then periodically call the `read_temperature()` method to get the data. Here I'm just printing it to the serial port.

And that's it! If you have the associated Python code from the course, you should be able to drop this code in place of what you had for the Arduino sketch before and see that the code operates just the same as using the library.

Reading a single piece of data is pretty straightforward, but most sensors you'll find which can be communicated to with SPI and I2C are similarly simple and follow the same pattern. Initialize and calibrate, then read raw data which you have to massage into a more useful format. If you ever find that the datasheet seems unclear, checking out existing libraries to see how they do it is usually a good start. Just keep in mind that there may be bugs, especially if the manufacturer didn't document their code properly.