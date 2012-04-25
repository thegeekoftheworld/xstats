<html>
    <head>
        <title>Xana Server Load</title>
        <script type="text/javascript" src="/static/smoothie.js"></script>
        <script type="text/javascript" src="/static/jquery-1.7.2.min.js"></script>
        <script type="text/javascript">
            function createChart(config)
            {
                return new SmoothieChart($.extend({
                    millisPerPixel: 100,
                    grid: {
                        fillStyle: '#000000',
                        strokeStyle: '#00FF00'
                    }
                }, config));
            }

            function colouredSeries(colour)
            {
                return {
                    strokeStyle: colour || '#00FF00',
                    fillStyle: 'rgba(0, 255, 0, 0.4)',
                    lineWidth: 3
                };
            }

            $(document).ready(function() {
                var charts = {
                    cpu: createChart({
                        minValue: 0,
                        maxValue: 4
                    }),
                    rtl: createChart({
                        maxValueScale: 1.05
                    }),
                    txp: createChart({
                        maxValueScale: 1.2,
                        minValue: 0,
                        maxValue: 100
                    }),
                    rxp: createChart({
                        maxValueScale: 1.2,
                        minValue: 0,
                        maxValue: 100
                    }),
                    txs: createChart({
                        maxValueScale: 1.2
                    }),
                    rxs: createChart({
                        maxValueScale: 1.2
                    })
                }

                var series = {
                    cpu: {
                        avg1min : new TimeSeries(),
                        avg5min : new TimeSeries(),
                        avg15min: new TimeSeries()
                    },
                    rtl: new TimeSeries(),
                    txp: new TimeSeries(),
                    rxp: new TimeSeries(),
                    txs: new TimeSeries(),
                    rxs: new TimeSeries()
                }

                var ws = new WebSocket("ws://127.0.0.1:8080/stats");

                ws.onopen = function(evt)
                {
                }
                ws.onmessage = function(evt)
                {
                    var data = $.parseJSON(evt.data);

                    series.cpu.avg1min.append(new Date().getTime(), parseFloat(data.cpu.avg[0]));
                    series.cpu.avg5min.append(new Date().getTime(), parseFloat(data.cpu.avg[1]));
                    series.cpu.avg15min.append(new Date().getTime(), parseFloat(data.cpu.avg[2]));

                    /*series.rtl.append(new Date().getTime(), parseInt(data.rtl));*/
                    /*series.txp.append(new Date().getTime(), parseInt(data.txp));*/
                    /*series.rxp.append(new Date().getTime(), parseInt(data.rxp));*/

                    series.txs.append(new Date().getTime(), parseInt(data.net['wlan0'].bytes_recv_sec));
                    series.rxs.append(new Date().getTime(), parseInt(data.net['wlan0'].bytes_sent_sec));

                    $("#cpu_val").html(data.cpu.avg[0]);
                    /*$("#rtl_val").html(data.rtl);*/
                    /*$("#txp_val").html(data.txp + "%");*/
                    /*$("#rxp_val").html(data.rxp + "%");*/
                    $("#txs_val").html(data.net['wlan0'].bytes_recv_sec)
                    $("#rxs_val").html(data.net['wlan0'].bytes_sent_sec)
                }

                charts.cpu.addTimeSeries(series.cpu.avg1min, colouredSeries());
                charts.cpu.addTimeSeries(series.cpu.avg5min, colouredSeries("#FFFF00"));
                charts.cpu.addTimeSeries(series.cpu.avg15min, colouredSeries("#FF0000"));

                for(var key in charts)
                {
                    if(key != "cpu")
                        charts[key].addTimeSeries(series[key], colouredSeries());

                    charts[key].streamTo(document.getElementById(key), 1000);
                }
            })
        </script>
        <style>
            body
            {
                background-color: #121212;
                color: #FFF;
                font-family: Verdana, Sans-serif;
            }
            .graph
            {
                width: 500px;
            }
            .graph:nth-child(odd)
            {
                float: left;
            }
            .graph:nth-child(even)
            {
                float: right;
            }

            .graph h1, .graph h2
            {
                float: left;
                margin-bottom: 5px;
            }
            .graph h2
            {
                float: right;
                position: relative;
                top: 10px;
            }
            .title
            {
                font-size: 48px;
            }

        </style>
    </head>
    <body>
        <center>
            <div style="width: 1100px;">
                <h1 class="title">Xana Creations :: Server Statistics</h1>
                <div class="graph">
                    <h1>CPU</h1>
                    <h2 id="cpu_val">...</h2>
                    <canvas id="cpu" width="500" height"150"></canvas>
                </div>
                <div class="graph">
                    <h1>Viewers</h1>
                    <h2 id="rtl_val">...</h2>
                    <canvas id="rtl" width="500" height"150"></canvas>
                </div>
                <div class="graph">
                    <h1>RX %</h1>
                    <h2 id="rxp_val">...</h2>
                    <canvas id="rxp" width="500" height"150"></canvas>
                </div>
                <div class="graph">
                    <h1>TX %</h1>
                    <h2 id="txp_val">...</h2>
                    <canvas id="txp" width="500" height"150"></canvas>
                </div>
                <div class="graph">
                    <h1>RX Throughput</h1>
                    <h2 id="rxs_val">...</h2>
                    <canvas id="rxs" width="500" height"150"></canvas>
                </div>
                <div class="graph">
                    <h1>TX Throughput</h1>
                    <h2 id="txs_val">...</h2>
                    <canvas id="txs" width="500" height"150"></canvas>
                </div>
            </div>
        </center>
    </body>
</html>
