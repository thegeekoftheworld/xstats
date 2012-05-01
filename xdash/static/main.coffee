toObject = (tuples) ->
    resultMap = {}
    (resultMap[key] = value) for [key, value] in tuples

    return resultMap

class Config
    constructor: (@config) ->

    sets: (chunkSize = 2) ->
        @config[i..i+chunkSize] for i in [0..@config.length - 1] by chunkSize

    namedSets: ->
        ({left: set[0], right: set[1]} for set in @sets())

    list: ->
        @config

class GaugeWrapper
    constructor: (@selector, @gauge, @data, @config) ->
        @label    = @data.getValue(0, 0)

    update: (value) ->
        @data.setValue(0, 1, value)
        @draw()

    draw: ->
        @gauge.draw(@data, @config)

init = ->
    config = new Config(configData)
    initLayout(config)
    graphs = initGraphs(config)
    #series = initSeries(graphs)
    gauges = initGauges(config)
    #socket = initWebsocket(config.websocketUri, series, gauges)

initLayout = (config) ->
    sets = config.namedSets()

    $("#container").html(
        $("#rowTemplate").render(sets)
    )

initGraphs = (config) ->
    sets = config.namedSets()
    graphs = {}

    pctDefaults = {
        maxvalue: 100,
        minvalue: 0,
    }

    for set, index in sets
        graphs["tx-pct-#{index}"] = new SmoothieChart(pctDefaults)
        graphs["rx-pct-#{index}"] = new SmoothieChart(pctDefaults)
        graphs["tx-val-#{index}"] = new SmoothieChart()
        graphs["rx-val-#{index}"] = new SmoothieChart()
        
    for graphId, graph of graphs
        graphDiv = $("##{graphId}").get(0)
        graph.streamTo(graphDiv)

    return graphs

initGauge = (selector, label = "NULL", initialValue = 0, maxValue = 100) ->
    selector = selector.replace(/\./g, "\\.")

    gaugeDiv = $(selector).get(0)
    gauge = new google.visualization.Gauge(gaugeDiv)

    initialData = google.visualization.arrayToDataTable([
        ['Label', 'Value'],
        [label, initialValue],
    ])

    defaultConfig = {
        width: 150,
        height: 400,
        animation: {
            easing: 'inAndOut'
        },
        max: maxValue
    }

    gaugeWrapper = new GaugeWrapper(selector, gauge, initialData, defaultConfig)
    gaugeWrapper.draw()

    return gaugeWrapper

initGauges = (config) ->
    gauges = []

    #return initTestGauge()

    for host in config.list()
        gauges.push(initGauge("##{host.hostname}-cpu"))
        gauges.push(initGauge("##{host.hostname}-mem"))

    toObject([gauge.selector, gauge] for gauge in gauges)

google.setOnLoadCallback ->
    init()

google.load('visualization', '1', {
    packages: ['gauge']
})
