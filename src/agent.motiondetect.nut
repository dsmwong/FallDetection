// Copyright (c) 2018, Electric Imp, Inc.
// Licence: MIT

// IMPORTS
#require "rocky.class.nut:2.0.2"

// CONSTANTS
const DATA_PER_SECOND = 50.0;
const TWO_PI = 6.283185307179586;
const HTML_DATA = @"
<html>
  <head>
    <script type='text/javascript'src='https://www.google.com/jsapi'></script>
    <script type='text/javascript' src='https://code.jquery.com/jquery-latest.js'></script>
    <script type='text/javascript'>
    google.load('visualization', '1', {packages: ['corechart', 'controls']});
    google.setOnLoadCallback(function() { drawVisualization('[]'); });
    var chart;
    function drawVisualization(chartData) {
      var dashboard = new google.visualization.Dashboard(document.getElementById('dashboard'));
      var control = new google.visualization.ControlWrapper({
        'controlType': 'ChartRangeFilter',
        'containerId': 'control',
        'options': {
          // Filter by the date axis.
          'filterColumnIndex': 0,
          'ui': { 'chartType': 'LineChart',
                  'chartOptions': { 'chartArea': {'width': '90%'},
                                    'hAxis': {'baselineColor': 'none'} },
                  // Display a single series that shows the closing value of the stock.
                  // Thus, this view has two columns: the date (axis) and the stock value (line series).
                  'chartView': { 'columns': [0, 1]},
                  // 1 day in milliseconds = 24 * 60 * 60 * 1000 = 86,400,000
                  'minRangeSize': 86400000 } },
      });
      chart = new google.visualization.ChartWrapper({
        'chartType': 'LineChart',
        'containerId': 'chart',
        'options': {
          // Use the same chart area width as the control for axis alignment.
          'chartArea': {'height': '80%', 'width': '90%'},
          'hAxis': {'slantedText': false, 'minorGridlines':{'count':'1'}},
          'vAxis': {'minorGridlines':{'count':'5'}},
          'legend': {'position': 'none'}},
      });
      var data = new google.visualization.DataTable();
      //columns
      data.addColumn('number','Time');
      data.addColumn('number','Level');
      //rows
      data.removeRows(0,data.getNumberOfRows());
      data.addRows(JSON.parse(chartData));
      dashboard.bind(control, chart);
      dashboard.draw(data);
    }
    function record(){
      $.ajax({
        type:'POST',
        url: window.location +'/start',
        data: '',
        success: drawVisualization,
        timeout: 120000,
        error: (function(err){
          console.log(err);
          console.log('Error parsing device info from imp');
          return;
        })
      });
    }
    function download(){
      console.log('Download it!');
      var uri = chart.getChart().getImageURI();
      var fn = document.getElementById('filename').value;
      var ld = document.getElementById('link_div');
      ld.innerHTML = '<a href='+uri+' id=""link_a"" download='+fn+'></a>';
      var la = document.getElementById('link_a');
      var clickEvent = document.createEvent('MouseEvent');
      clickEvent.initMouseEvent('click', true, true, window, 0, 0, 0, 0, 0, false, false, false, false, 0, null);
      document.getElementById('link_a').dispatchEvent(clickEvent);
    }
    var interval = null;
    function start(){
      document.getElementById('start_mode').disabled = true;
      document.getElementById('wakeup_mode').disabled = false;
      interval = setInterval(function() {
        record();
      }, 5000);
    }
    function wakeup(){
      document.getElementById('start_mode').disabled = false;
      document.getElementById('wakeup_mode').disabled = true;
      $.ajax({
        type:'POST',
        url: window.location +'/wakeup',
        data: '',
        success: drawVisualization,
        timeout: 120000,
        error: (function(err){
          console.log(err);
          console.log('Error parsing device info from imp');
          return;
        })
      });  
    }
    </script>
  </head>
  <body>
    <button type='button' id='start_mode' onclick='start()'>Continuous Mode</button>
    <button type='button' id='wakeup_mode' onclick='wakeup()'>Wakeup Mode</button>
    <div id='dashboard' style='width: 100%%'>
      <div id='chart' style='width: 99%%; height: 400px;'></div>
      <div id='control' style='width: 99%%; height: 50px;'></div>
    </div>
    <p><p>
    <div id='download_div'>
      <input type='button' value='Download' onclick='download();'>
      <input type='text' id='filename' value='impact_test'>
    </div>
    <div id='link_div'></div>
  </body>
</html>";

// GLOBALS
savedContext <- null; // Web app request context
savedValues <- null; // collected accelerometer data

// RUNTIME

// Set up the handler function for data received from the device
device.on("accelData", function(values) {
    savedValues = [[0, 0]];
    savedValues.clear();
  
    // Fast Fourier Transform the incoming data
    local len = values.len() / 4;
  
    // Prepare a frequency domain visualization
    local result = blob(len);
    local arrReal = array(len,0.0);
    local arrImag = array(len,0.0);
    local invlen = 1.0 / len;
    for (local i = 0 ; i < len ; i++) {
        values.seek(0);      
        for (local n = 0 ; n < len ; n++) {
            local theta = TWO_PI * i * n * invlen;
            local costheta = math.cos(theta);
            local sintheta = math.sin(theta);
            local valueMag = values.readn('f');
            arrReal[i] += valueMag * costheta;
            arrImag[i] += valueMag * sintheta;
        }
    
        arrReal[i] *= invlen;
        arrImag[i] *= invlen;
        savedValues.append([i + 1, math.sqrt(arrReal[i] * arrReal[i] + arrImag[i] * arrImag[i])]);
    }

    server.log("Graphing the accelerometer data");
  
    // send the decoded data along to the web app to be graphed
    imp.wakeup(0, function() { 
        savedContext.send(200, http.jsonencode(savedValues));
    });
});

// Set up the agent's API
api <- Rocky({"timeout": 64000});

// Serve the web UI to any GET request to the root agent URL
api.get("/", function(context) { 
    context.send(200, HTML_DATA);
});

// Start collecting data when requested by the web app, ie.
// the user clicks the 'Continuous Mode' button
api.post("/start", function(context) {
    server.log("Collecting accelerometer sample");
  
    // Send the 'start' message to the device to request data
    device.send("start", null);
  
    // hold the request context so that data can be sent back
    // to the web UI when the device has collected data
    savedContext = context;
});

// Start collecting data when requested by the web app, ie.
// the user clicks the 'Wakeup Mode' button
api.post("/wakeup", function(context) {
    server.log("Entering Wakeup mode");
  
    // Send the 'wakeup' message to the device to put into the correct mode
    device.send("wakeup", null);
  
    // Hold the request context so that BlinkUp data can be sent back
    // to this web UI when the device has collected data
    savedContext = context;
});