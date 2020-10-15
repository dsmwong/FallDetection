// Copyright (c) 2018, Electric Imp, Inc.
// Licence: MIT

// IMPORTS
#require "LIS3DH.device.lib.nut:2.0.1"

// CONSTANTS
const LENGTH_OF_ACQUISITION = 2.56;
const DATA_PER_SECOND = 100;

// 'GLOBALS'
local totalAquiredData = 4 * LENGTH_OF_ACQUISITION * DATA_PER_SECOND;
local accelerometerData = blob(totalAquiredData);
local wakeupMode = false; 

wakePin <- hardware.pin1;
i2c <- hardware.i2c89;

// Configure the I2C bus and the acceleromter connected to it
i2c.configure(CLOCK_SPEED_400_KHZ);
accelerometer <- LIS3DH(i2c, 0x32);
accelerometer.setDataRate(DATA_PER_SECOND);
accelerometer.setRange(8);

// FUNCTIONS
function readBuffer() {

    server.log("readBuffer");
    // Read a block of data from the accelerometer's FIFO buffer
    if (wakePin.read() == 0) return;

    // Read the buffer
    local stats = accelerometer.getFifoStats();

    // Run through the received FIFO data and package the data values
    for (local i = 0 ; i < stats.unread ; i++) {
        local data = accelerometer.getAccel();
        accelerometerData.writen(data.x, 'f');
        
        server.log("packing data");
        if (accelerometerData.eos() != null) {
            // Send the current batch of readings to the agent for graphing
            agent.send("accelData", accelerometerData);
            //i = stats.unread;

            // If we are in wakeup mode, put the impExplorer back to sleep 
            // and awaiting the next wake interrupt
            if (wakeupMode) {
                // Configure pin 1 to wake the impExplorer
                hardware.pin1.configure(DIGITAL_IN_WAKEUP);
        
                // Configure the accelerometer to signal pin 1 upon detecting movement
                accelerometer.configureClickInterrupt(true, LIS3DH_SINGLE_CLICK);
                accelerometer.configureFifoInterrupt(false, LIS3DH_FIFO_BYPASS_MODE);
        
                // Put the impExplorer to sleep as soon as it (ie. impOS) goes idle
                imp.onidle(function() {
                    server.log("impExlorer has nothing to do, so is going to sleep for 30 mins");
                    server.sleepfor(1800);
                });
            } else {
                // We are in continuous reading mode, so don't sleep, 
                // just wait for a subsequent Start command
                accelerometer.configureFifoInterrupt(false, LIS3DH_FIFO_BYPASS_MODE);
            }

            break;
        }
    }
}

// Set up command handlers by registering the functions that will be called
// upon receipt of the specified messages from the agent (they are triggered
// in response to button clicks in the agent-served browser UI)

// Normal data acquisition mode: collect accelerometer data and  
// send it to the agent periodically for graphing
agent.on("start", function(dummy) {
    // Put the data store (blob) pointer back to the start of the store
    accelerometerData.seek(0);
  
    // Configure the accelerometer's FIFO buffer in Stream Mode and set the interrupt generator
    accelerometer.configureFifoInterrupt(true, LIS3DH_FIFO_STREAM_MODE, 30);
  
    // Configure the impExplorer's interrupt pin, which will be triggered by the accelerometer.
    // In turn, this will trigger a call to the function 'readBuffer()'
    wakePin.configure(DIGITAL_IN_PULLDOWN, readBuffer);
  
    wakeupMode = false;
});

// Set the impExplorer to wakeup mode, ie. stop regular data collection and instead
// put the impExplorer to sleep to wait to be woken by the accelerometer
agent.on("wakeup", function(dummy) {
    // Configure pin 1 to wake the impExplorer
    wakePin.configure(DIGITAL_IN_WAKEUP);

    // Configure the accelerometer to signal pin 1 upon detecting movement
    accelerometer.configureClickInterrupt(true, LIS3DH_SINGLE_CLICK);
    accelerometer.configureFifoInterrupt(false, LIS3DH_FIFO_BYPASS_MODE);
  
    // Put the impExplorer to sleep as soon as it (ie. impOS) goes idle
    imp.onidle(function() {
        server.log("impExlorer has nothing to do, so is going to sleep for 30 mins");
        server.sleepfor(1800);
    });
});

// In the final section of the code, we check if the impExplorer was woken by an
// assertion of the wakeup pin. If it was - as configured by a request for wakeup mode 
// (see above) - then begin collecting accelerometer data to graph
if (WAKEREASON_PIN == hardware.wakereason()) {
    // Put the data store (blob) pointer back to the start of the store
    accelerometerData.seek(0);
  
    // Configure the FIFO buffer in Stream Mode and set the interrupt generator
    accelerometer.configureClickInterrupt(false, LIS3DH_SINGLE_CLICK);    
    accelerometer.configureFifoInterrupt(true, LIS3DH_FIFO_STREAM_MODE, 30);
  
    // Configure the impExplorer's interrupt pin, which will be triggered by the accelerometer.
    // In turn, this will trigger a call to the function 'readBuffer()'
    wakePin.configure(DIGITAL_IN_PULLDOWN, readBuffer);
  
    wakeupMode = true;
}