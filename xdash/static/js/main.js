// Generated by CoffeeScript 1.3.1
(function() {
  var Application, Config, GaugeWrapper, colouredSeries, roundToDecimal, toObject;

  toObject = function(tuples) {
    var key, resultMap, value, _i, _len, _ref;
    resultMap = {};
    for (_i = 0, _len = tuples.length; _i < _len; _i++) {
      _ref = tuples[_i], key = _ref[0], value = _ref[1];
      resultMap[key] = value;
    }
    return resultMap;
  };

  roundToDecimal = function(number, decimals) {
    var multiplier;
    multiplier = Math.pow(10, decimals);
    return Math.round(number * multiplier) / multiplier;
  };

  colouredSeries = function(colour) {
    return {
      strokeStyle: 'rgba(' + (colour || '0, 255, 0') + ', 1)',
      fillStyle: 'rgba(' + (colour || '0, 255, 0') + ', 0.4)',
      lineWidth: 3
    };
  };

  Application = (function() {

    Application.name = 'Application';

    function Application(configData) {
      this.config = new Config(configData);
      this.graphs = {};
      this.series = {};
      this.gauges = {};
      this.socket = void 0;
    }

    Application.prototype.init = function() {
      this.initLayout();
      this.initGraphs();
      this.initSeries();
      this.initGauges();
      return this.initWebsocket(this.config.get('websocketUri'));
    };

    Application.prototype.initLayout = function() {
      var sets;
      sets = this.config.namedSets();
      return $("#container").html($("#rowTemplate").render(sets));
    };

    Application.prototype.initGraphs = function() {
      var defaults, graph, graphDiv, graphId, index, pctDefaults, set, sets, _i, _len, _ref, _results;
      sets = this.config.namedSets();
      defaults = {
        millisPerPixel: 50,
        grid: {
          millisPerLine: 2500,
          verticalSections: 2,
          fillStyle: '#000000',
          strokeStyle: '#444444',
          lineWidth: 1
        }
      };
      pctDefaults = $.extend({
        maxvalue: 100,
        minvalue: 0
      }, defaults);
      for (index = _i = 0, _len = sets.length; _i < _len; index = ++_i) {
        set = sets[index];
        this.graphs["sent-pct-" + index] = new SmoothieChart(pctDefaults);
        this.graphs["recv-pct-" + index] = new SmoothieChart(pctDefaults);
        this.graphs["sent-val-" + index] = new SmoothieChart(defaults);
        this.graphs["recv-val-" + index] = new SmoothieChart(defaults);
      }
      _ref = this.graphs;
      _results = [];
      for (graphId in _ref) {
        graph = _ref[graphId];
        graphDiv = $("#" + graphId).get(0);
        _results.push(graph.streamTo(graphDiv, 2000));
      }
      return _results;
    };

    Application.prototype.initSeries = function() {
      var host, hosts, i, leftSeries, rightSeries, set, sets, _i, _j, _len, _len1, _results;
      sets = this.config.sets();
      hosts = this.config.list();
      for (_i = 0, _len = hosts.length; _i < _len; _i++) {
        host = hosts[_i];
        this.series[host.hostname] = {};
        this.series[host.hostname]["sent-pct"] = new TimeSeries();
        this.series[host.hostname]["recv-pct"] = new TimeSeries();
        this.series[host.hostname]["sent-val"] = new TimeSeries();
        this.series[host.hostname]["recv-val"] = new TimeSeries();
      }
      _results = [];
      for (i = _j = 0, _len1 = sets.length; _j < _len1; i = ++_j) {
        set = sets[i];
        leftSeries = this.series[set[0].hostname];
        rightSeries = this.series[set[1].hostname];
        this.graphs["sent-pct-" + i].addTimeSeries(leftSeries["sent-pct"], colouredSeries('0, 255, 0'));
        this.graphs["recv-pct-" + i].addTimeSeries(leftSeries["recv-pct"], colouredSeries('0, 255, 0'));
        this.graphs["sent-val-" + i].addTimeSeries(leftSeries["sent-val"], colouredSeries('0, 255, 0'));
        this.graphs["recv-val-" + i].addTimeSeries(leftSeries["recv-val"], colouredSeries('0, 255, 0'));
        this.graphs["sent-pct-" + i].addTimeSeries(rightSeries["sent-pct"], colouredSeries('255, 0, 0'));
        this.graphs["recv-pct-" + i].addTimeSeries(rightSeries["recv-pct"], colouredSeries('255, 0, 0'));
        this.graphs["sent-val-" + i].addTimeSeries(rightSeries["sent-val"], colouredSeries('255, 0, 0'));
        _results.push(this.graphs["recv-val-" + i].addTimeSeries(rightSeries["recv-val"], colouredSeries('255, 0, 0')));
      }
      return _results;
    };

    Application.prototype.initGauges = function() {
      var gauge, gaugeList, host, _i, _len, _ref;
      gaugeList = [];
      _ref = this.config.list();
      for (_i = 0, _len = _ref.length; _i < _len; _i++) {
        host = _ref[_i];
        gaugeList.push(this.initGauge(host.hostname, "cpu", "CPU"));
        gaugeList.push(this.initGauge(host.hostname, "mem", "RAM", this.config.hostGet(host.hostname, 'ram')));
      }
      return this.gauges = toObject((function() {
        var _j, _len1, _results;
        _results = [];
        for (_j = 0, _len1 = gaugeList.length; _j < _len1; _j++) {
          gauge = gaugeList[_j];
          _results.push(["" + gauge.hostname + "-" + gauge.type, gauge]);
        }
        return _results;
      })());
    };

    Application.prototype.initGauge = function(hostname, type, label, maxValue, initialValue) {
      var defaultConfig, gauge, gaugeDiv, gaugeWrapper, initialData, selector;
      if (label == null) {
        label = "NULL";
      }
      if (maxValue == null) {
        maxValue = 100;
      }
      if (initialValue == null) {
        initialValue = 0;
      }
      selector = ("#" + hostname + "-" + type).replace(/\./g, "\\.");
      gaugeDiv = $(selector).get(0);
      gauge = new google.visualization.Gauge(gaugeDiv);
      initialData = google.visualization.arrayToDataTable([['Label', 'Value'], [label, initialValue]]);
      defaultConfig = {
        width: 150,
        height: 150,
        max: maxValue,
        animation: {
          easing: 'inAndOut'
        }
      };
      gaugeWrapper = new GaugeWrapper(hostname, type, gauge, initialData, defaultConfig);
      gaugeWrapper.draw();
      return gaugeWrapper;
    };

    Application.prototype.initWebsocket = function(uri) {
      var socket, that;
      socket = new WebSocket(uri);
      that = this;
      socket.onopen = function(evt) {
        return console.log("Connected to " + uri);
      };
      return socket.onmessage = function(evt) {
        return that.handleWebsocketMessage(evt.data);
      };
    };

    Application.prototype.handleWebsocketMessage = function(data) {
      var escapedHostname, hostname, packet, rxPct, time, txPct, usedMemory;
      packet = $.parseJSON(data);
      hostname = packet.host;
      escapedHostname = hostname.replace(/\./g, "\\.");
      time = new Date().getTime();
      switch (packet.module) {
        case "network":
          this.series[hostname]["sent-val"].append(time, packet.data['bytes-sent'] / 1024);
          this.series[hostname]["recv-val"].append(time, packet.data['bytes-recv'] / 1024);
          txPct = packet.data['bytes-sent'] / this.config.get(hostname, 'bandwidth') * 100;
          rxPct = packet.data['bytes-recv'] / this.config.get(hostname, 'bandwidth') * 100;
          this.series[hostname]["sent-pct"].append(time, txPct);
          this.series[hostname]["recv-pct"].append(time, rxPct);
          $("#sent-txt-" + escapedHostname).html(roundToDecimal(packet.data['bytes-sent'] / 1024, 2));
          return $("#recv-txt-" + escapedHostname).html(roundToDecimal(packet.data['bytes-recv'] / 1024, 2));
        case "memory":
          usedMemory = Math.round(this.config.hostGet(hostname, 'ram') * packet.data['physical-percent'] / 100);
          return this.gauges["" + hostname + "-mem"].update(usedMemory);
        case "cpu":
          return this.gauges["" + hostname + "-cpu"].update(packet.data.avg);
      }
    };

    return Application;

  })();

  Config = (function() {

    Config.name = 'Config';

    function Config(data) {
      var host;
      this.data = data;
      this.hosts = toObject((function() {
        var _i, _len, _ref, _results;
        _ref = this.data.hosts;
        _results = [];
        for (_i = 0, _len = _ref.length; _i < _len; _i++) {
          host = _ref[_i];
          _results.push([host.hostname, host]);
        }
        return _results;
      }).call(this));
    }

    Config.prototype.get = function(key) {
      return this.data[key];
    };

    Config.prototype.hostGet = function(host, key) {
      return this.hosts[host][key];
    };

    Config.prototype.sets = function(chunkSize) {
      var i, _i, _ref, _results;
      if (chunkSize == null) {
        chunkSize = 2;
      }
      _results = [];
      for (i = _i = 0, _ref = this.data.hosts.length - 1; 0 <= _ref ? _i <= _ref : _i >= _ref; i = _i += chunkSize) {
        _results.push(this.data.hosts.slice(i, (i + chunkSize) + 1 || 9e9));
      }
      return _results;
    };

    Config.prototype.namedSets = function() {
      var set, _i, _len, _ref, _results;
      _ref = this.sets();
      _results = [];
      for (_i = 0, _len = _ref.length; _i < _len; _i++) {
        set = _ref[_i];
        _results.push({
          left: set[0],
          right: set[1]
        });
      }
      return _results;
    };

    Config.prototype.list = function() {
      return this.data.hosts;
    };

    return Config;

  })();

  GaugeWrapper = (function() {

    GaugeWrapper.name = 'GaugeWrapper';

    function GaugeWrapper(hostname, type, gauge, data, config) {
      this.hostname = hostname;
      this.type = type;
      this.gauge = gauge;
      this.data = data;
      this.config = config;
      this.label = this.data.getValue(0, 0);
    }

    GaugeWrapper.prototype.update = function(value) {
      this.data.setValue(0, 1, value);
      return this.draw();
    };

    GaugeWrapper.prototype.draw = function() {
      return this.gauge.draw(this.data, this.config);
    };

    return GaugeWrapper;

  })();

  google.setOnLoadCallback(function() {
    var app;
    app = new Application(configData);
    return app.init();
  });

  google.load('visualization', '1', {
    packages: ['gauge']
  });

}).call(this);
