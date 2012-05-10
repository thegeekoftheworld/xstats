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
            $("#rowTemplate").render(sets, {
                unit: if @config.get('bits') then 'kb/s' else 'KB/s'
            })
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
            },
            minValue: 0,
        }
        pctDefaults = $.extend({
            maxValue: 100
        }, defaults)

        for set, index in sets
            @graphs["sent-pct-#{index}"] = new SmoothieChart(pctDefaults)
            @graphs["recv-pct-#{index}"] = new SmoothieChart(pctDefaults)
            @graphs["sent-val-#{index}"] = new SmoothieChart(defaults)
            @graphs["recv-val-#{index}"] = new SmoothieChart(defaults)

        for graphId, graph of @graphs
            graphDiv = $("##{graphId}").get(0)
            graph.streamTo(graphDiv, 2000)

    initSeries: () ->
        sets   = @config.sets()
        hosts  = @config.list()

        for host in hosts
            @series[host.hostname] = {}

            @series[host.hostname]["sent-pct"] = new TimeSeries()
            @series[host.hostname]["recv-pct"] = new TimeSeries()
            @series[host.hostname]["sent-val"] = new TimeSeries()
            @series[host.hostname]["recv-val"] = new TimeSeries()

        for set, i in sets
            leftSeries  = @series[set[0].hostname]
            rightSeries = @series[set[1].hostname]

            @graphs["sent-pct-#{i}"].addTimeSeries(
                leftSeries["sent-pct"], colouredSeries('0, 255, 0'))
            @graphs["recv-pct-#{i}"].addTimeSeries(
                leftSeries["recv-pct"], colouredSeries('0, 255, 0'))
            @graphs["sent-val-#{i}"].addTimeSeries(
                leftSeries["sent-val"], colouredSeries('0, 255, 0'))
            @graphs["recv-val-#{i}"].addTimeSeries(
                leftSeries["recv-val"], colouredSeries('0, 255, 0'))

            @graphs["sent-pct-#{i}"].addTimeSeries(
                rightSeries["sent-pct"], colouredSeries('255, 0, 0'))
            @graphs["recv-pct-#{i}"].addTimeSeries(
                rightSeries["recv-pct"], colouredSeries('255, 0, 0'))
            @graphs["sent-val-#{i}"].addTimeSeries(
                rightSeries["sent-val"], colouredSeries('255, 0, 0'))
            @graphs["recv-val-#{i}"].addTimeSeries(
                rightSeries["recv-val"], colouredSeries('255, 0, 0'))

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
                txVal = packet.data['bytes-sent'] / 1024
                rxVal = packet.data['bytes-recv'] / 1024

                txPct = txVal / @config.hostGet(hostname, 'bandwidth') * 100
                rxPct = rxVal / @config.hostGet(hostname, 'bandwidth') * 100

                @series[hostname]["sent-pct"].append(time, txPct)
                @series[hostname]["recv-pct"].append(time, rxPct)

                if @config.get('bits')
                    txVal *= 8
                    rxVal *= 8

                @series[hostname]["sent-val"].append(time, txVal)
                @series[hostname]["recv-val"].append(time, rxVal)

                $("#sent-txt-#{escapedHostname}").html(
                    roundToDecimal(txVal, 2)
                )
                $("#recv-txt-#{escapedHostname}").html(
                    roundToDecimal(rxVal, 2)
                )
                $("#sent-pct-txt-#{escapedHostname}").html(
                    roundToDecimal(txPct, 2)
                )
                $("#recv-pct-txt-#{escapedHostname}").html(
                    roundToDecimal(rxPct, 2)
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
