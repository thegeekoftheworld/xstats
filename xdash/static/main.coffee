toObject = (tuples) ->
    resultMap = {}
    (resultMap[key] = value) for [key, value] in tuples

    return resultMap

roundToDecimal = (number, decimals) ->
    multiplier = Math.pow(10, decimals)

    return Math.round(number * multiplier) / multiplier

colouredSeries = (colour) ->
    {
        strokeStyle: 'rgba(' + (colour || '0, 255, 0') + ', 1)',
        fillStyle  : 'rgba(' + (colour || '0, 255, 0') + ', 0.4)',
        lineWidth  : 3
    }


class Application
    constructor: (configData) ->
        @config = new Config(configData)

        @graphs = {}
        @series = {}
        @gauges = {}
        @socket = undefined

    init: ->
        @initLayout()
        @initGraphs()
        @initSeries()
        @initGauges()
        @initWebsocket(@config.get('websocketUri'))

    initLayout: ->
        sets = @config.namedSets()

        $("#container").html(
            $("#rowTemplate").render(sets)
        )

    initGraphs: ->
        sets = @config.namedSets()

        defaults = {
            millisPerPixel: 50,
            grid: {
                millisPerLine: 2500,
                verticalSections: 2,
                fillStyle: '#000000',
                strokeStyle: '#444444',
                lineWidth: 1
            }
        }
        pctDefaults = $.extend({
            maxvalue: 100,
            minvalue: 0,
        }, defaults)

        for set, index in sets
            @graphs["tx-pct-#{index}"] = new SmoothieChart(pctDefaults)
            @graphs["rx-pct-#{index}"] = new SmoothieChart(pctDefaults)
            @graphs["tx-val-#{index}"] = new SmoothieChart(defaults)
            @graphs["rx-val-#{index}"] = new SmoothieChart(defaults)

        for graphId, graph of @graphs
            graphDiv = $("##{graphId}").get(0)
            graph.streamTo(graphDiv, 2000)

    initSeries: () ->
        sets   = @config.sets()
        hosts  = @config.list()

        for host in hosts
            @series[host.hostname] = {}

            @series[host.hostname]["tx-pct"] = new TimeSeries()
            @series[host.hostname]["rx-pct"] = new TimeSeries()
            @series[host.hostname]["tx-val"] = new TimeSeries()
            @series[host.hostname]["rx-val"] = new TimeSeries()

        for set, i in sets
            leftSeries  = @series[set[0].hostname]
            rightSeries = @series[set[1].hostname]

            @graphs["tx-pct-#{i}"].addTimeSeries(
                leftSeries["tx-pct"], colouredSeries('0, 255, 0'))
            @graphs["rx-pct-#{i}"].addTimeSeries(
                leftSeries["rx-pct"], colouredSeries('0, 255, 0'))
            @graphs["tx-val-#{i}"].addTimeSeries(
                leftSeries["tx-val"], colouredSeries('0, 255, 0'))
            @graphs["rx-val-#{i}"].addTimeSeries(
                leftSeries["rx-val"], colouredSeries('0, 255, 0'))

            @graphs["tx-pct-#{i}"].addTimeSeries(
                rightSeries["tx-pct"], colouredSeries('255, 0, 0'))
            @graphs["rx-pct-#{i}"].addTimeSeries(
                rightSeries["rx-pct"], colouredSeries('255, 0, 0'))
            @graphs["tx-val-#{i}"].addTimeSeries(
                rightSeries["tx-val"], colouredSeries('255, 0, 0'))
            @graphs["rx-val-#{i}"].addTimeSeries(
                rightSeries["rx-val"], colouredSeries('255, 0, 0'))

    initGauges: ->
        gaugeList = []

        for host in @config.list()
            gaugeList.push(@initGauge(host.hostname, "cpu", "CPU"))
            gaugeList.push(@initGauge(
                host.hostname, "mem", "RAM", @config.hostGet(host.hostname, 'ram')
            ))

        @gauges = toObject(
            ["#{gauge.hostname}-#{gauge.type}", gauge] for gauge in gaugeList
        )

    initGauge: (hostname, type, label = "NULL", maxValue = 100, initialValue = 0) ->
        selector = "##{hostname}-#{type}".replace(/\./g, "\\.")

        gaugeDiv = $(selector).get(0)
        gauge = new google.visualization.Gauge(gaugeDiv)

        initialData = google.visualization.arrayToDataTable([
            ['Label', 'Value'],
            [label, initialValue],
        ])

        defaultConfig = {
            width : 150,
            height: 150,
            max   : maxValue,
            animation: {
                easing: 'inAndOut'
            }
        }

        gaugeWrapper = new GaugeWrapper(hostname, type, gauge,
                                        initialData, defaultConfig)
        gaugeWrapper.draw()

        gaugeWrapper

    initWebsocket: (uri) ->
        socket = new WebSocket(uri)
        that   = @

        socket.onopen = (evt) ->
            console.log("Connected to #{uri}")

        socket.onmessage = (evt) ->
            that.handleWebsocketMessage(evt.data)

    handleWebsocketMessage: (data) ->
        packet          = $.parseJSON(data)
        hostname        = packet.host
        escapedHostname = hostname.replace(/\./g, "\\.")
        time            = new Date().getTime()

        switch packet.module
            when "network"
                @series[hostname]["tx-val"].append(time, packet.data['bytes-sent'] / 1024)
                @series[hostname]["rx-val"].append(time, packet.data['bytes-recv'] / 1024)

                txPct = packet.data['bytes-sent'] / @config.get(hostname, 'bandwidth') * 100
                rxPct = packet.data['bytes-recv'] / @config.get(hostname, 'bandwidth') * 100

                @series[hostname]["tx-pct"].append(time, txPct)
                @series[hostname]["rx-pct"].append(time, rxPct)

                $("#tx-txt-#{escapedHostname}").html(
                    roundToDecimal(packet.data['bytes-sent'] / 1024, 2)
                )
                $("#rx-txt-#{escapedHostname}").html(
                    roundToDecimal(packet.data['bytes-recv'] / 1024, 2)
                )
            when "memory"
                usedMemory = Math.round(
                    @config.hostGet(hostname, 'ram') *
                    packet.data['physical-percent'] /
                    100
                )

                @gauges["#{hostname}-mem"].update(usedMemory)
            when "cpu"
                @gauges["#{hostname}-cpu"].update(packet.data.avg)

class Config
    constructor: (@data) ->
        @hosts = toObject([host.hostname, host] for host in @data.hosts)

    get: (key) ->
        @data[key]

    hostGet: (host, key) ->
        @hosts[host][key]

    sets: (chunkSize = 2) ->
        @data.hosts[i..i+chunkSize] for i in [0..@data.hosts.length - 1] by chunkSize

    namedSets: ->
        ({left: set[0], right: set[1]} for set in @sets())

    list: ->
        @data.hosts

class GaugeWrapper
    constructor: (@hostname, @type, @gauge, @data, @config) ->
        @label = @data.getValue(0, 0)

    update: (value) ->
        @data.setValue(0, 1, value)
        @draw()

    draw: ->
        @gauge.draw(@data, @config)

google.setOnLoadCallback ->
    app = new Application(configData)
    app.init()

google.load('visualization', '1', {
    packages: ['gauge']
})
