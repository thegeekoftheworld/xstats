toObject = (tuples) ->
    resultMap = {}
    (resultMap[key] = value) for [key, value] in tuples

    return resultMap

roundToDecimal = (number, decimals) ->
    multiplier = Math.pow(10, decimals)

    return Math.round(number * multiplier) / multiplier

colouredSeries = (colour, stroke = false) ->
    data = {
        lineWidth  : 3
    }

    if stroke
        data.strokeStyle = 'rgba(' + (colour || '0, 255, 0') + ', 1)'
        data.fillStyle = 'rgba(' + (colour || '0, 255, 0') + ', 0)'
    else
        data.strokeStyle = 'rgba(' + (colour || '0, 255, 0') + ', 0)'
        data.fillStyle = 'rgba(' + (colour || '0, 255, 0') + ', 0.4)'

    return data


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

            @series[host.hostname]["sent-pct-cur"] = new TimeSeries()
            @series[host.hostname]["recv-pct-cur"] = new TimeSeries()
            @series[host.hostname]["sent-val-cur"] = new TimeSeries()
            @series[host.hostname]["recv-val-cur"] = new TimeSeries()

            @series[host.hostname]["sent-pct-avg"] = new TimeSeries()
            @series[host.hostname]["recv-pct-avg"] = new TimeSeries()
            @series[host.hostname]["sent-val-avg"] = new TimeSeries()
            @series[host.hostname]["recv-val-avg"] = new TimeSeries()

        for set, i in sets
            leftSeries  = @series[set[0].hostname]
            rightSeries = @series[set[1].hostname]

            @graphs["sent-pct-#{i}"].addTimeSeries(
                leftSeries["sent-pct-cur"], colouredSeries('0, 255, 0'))
            @graphs["recv-pct-#{i}"].addTimeSeries(
                leftSeries["recv-pct-cur"], colouredSeries('0, 255, 0'))
            @graphs["sent-val-#{i}"].addTimeSeries(
                leftSeries["sent-val-cur"], colouredSeries('0, 255, 0'))
            @graphs["recv-val-#{i}"].addTimeSeries(
                leftSeries["recv-val-cur"], colouredSeries('0, 255, 0'))

            @graphs["sent-pct-#{i}"].addTimeSeries(
                rightSeries["sent-pct-cur"], colouredSeries('255, 0, 0'))
            @graphs["recv-pct-#{i}"].addTimeSeries(
                rightSeries["recv-pct-cur"], colouredSeries('255, 0, 0'))
            @graphs["sent-val-#{i}"].addTimeSeries(
                rightSeries["sent-val-cur"], colouredSeries('255, 0, 0'))
            @graphs["recv-val-#{i}"].addTimeSeries(
                rightSeries["recv-val-cur"], colouredSeries('255, 0, 0'))
                
            @graphs["sent-pct-#{i}"].addTimeSeries(
                leftSeries["sent-pct-avg"], colouredSeries('0, 255, 0', true))
            @graphs["recv-pct-#{i}"].addTimeSeries(
                leftSeries["recv-pct-avg"], colouredSeries('0, 255, 0', true))
            @graphs["sent-val-#{i}"].addTimeSeries(
                leftSeries["sent-val-avg"], colouredSeries('0, 255, 0', true))
            @graphs["recv-val-#{i}"].addTimeSeries(
                leftSeries["recv-val-avg"], colouredSeries('0, 255, 0', true))

            @graphs["sent-pct-#{i}"].addTimeSeries(
                rightSeries["sent-pct-avg"], colouredSeries('255, 0, 0', true))
            @graphs["recv-pct-#{i}"].addTimeSeries(
                rightSeries["recv-pct-avg"], colouredSeries('255, 0, 0', true))
            @graphs["sent-val-#{i}"].addTimeSeries(
                rightSeries["sent-val-avg"], colouredSeries('255, 0, 0', true))
            @graphs["recv-val-#{i}"].addTimeSeries(
                rightSeries["recv-val-avg"], colouredSeries('255, 0, 0', true))

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

    convertBytesToValues: (hostname, val) ->
        val /= 1024
        pct = val / @config.hostGet(hostname, 'bandwidth') * 100

        if @config.get('bits')
            val *= 8
        

        return {'val': val, 'pct': pct}

    handleWebsocketMessage: (data) ->
        packet          = $.parseJSON(data)
        hostname        = packet.host
        escapedHostname = hostname.replace(/\./g, "\\.")
        time            = new Date().getTime()

        switch packet.module
            when "network"
                tx = @convertBytesToValues(hostname, packet.data['bytes-sent'])
                rx = @convertBytesToValues(hostname, packet.data['bytes-recv'])

                @series[hostname]["sent-pct-cur"].append(time, tx.pct)
                @series[hostname]["recv-pct-cur"].append(time, rx.pct)
                @series[hostname]["sent-val-cur"].append(time, tx.val)
                @series[hostname]["recv-val-cur"].append(time, rx.val)

                $("#sent-pct-txt-#{escapedHostname}").html(
                    roundToDecimal(tx.pct, 2)
                )
                $("#recv-pct-txt-#{escapedHostname}").html(
                    roundToDecimal(rx.pct, 2)
                )
                $("#sent-txt-#{escapedHostname}").html(
                    roundToDecimal(tx.val, 2)
                )
                $("#recv-txt-#{escapedHostname}").html(
                    roundToDecimal(rx.val, 2)
                )
            when "bandwidth-rolling"
                if "average-" + @config.hostGet(hostname, 'iface') + "-out" not of packet.data
                    return

                tx = @convertBytesToValues(hostname, packet.data["average-" + @config.hostGet(hostname, 'iface') + "-out"])
                rx = @convertBytesToValues(hostname, packet.data["average-" + @config.hostGet(hostname, 'iface') + "-in"])

                @series[hostname]["sent-val-avg"].append(time, tx.val)
                @series[hostname]["recv-val-avg"].append(time, rx.val)

                @series[hostname]["sent-pct-avg"].append(time, tx.pct)
                @series[hostname]["recv-pct-avg"].append(time, rx.pct)

                #$("#sent-pct-txt-#{escapedHostname}").html(
                #    roundToDecimal(tx.val, 2)
                #)
                #$("#recv-pct-txt-#{escapedHostname}").html(
                #    roundToDecimal(rx.val, 2)
                #)
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
