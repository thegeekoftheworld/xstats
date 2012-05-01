class Config
    constructor: (@config) ->

    sets: (chunkSize = 2) ->
        @config[i..i+chunkSize] for i in [0..@config.length - 1] by chunkSize

init = ->
    config = new Config(configData)
    initLayout(config)
    #graphs = initGraphs()
    #series = initSeries(graphs)
    #gauges = initGauges()
    #socket = initWebsocket(config.websocketUri, series, gauges)

initLayout = (config) ->
    sets = config.sets()
    namedSets = ({left: set[0], right: set[1]} for set in sets)

    $("#container").html(
        $("#rowTemplate").render(namedSets)
    )

initGraphs = ->
    pctConfig = {
        maxvalue: 100,
        minvalue: 0,
    }

    graphs = {
        'txPct': new SmoothieChart(pctConfig)
        'rxPct': new SmoothieChart(pctConfig)
        'txVal': new SmoothieChart()
        'rxVal': new SmoothieChart()
    }

    for graphId, graph of graphs
        graphDiv = $("##{graphId}").get(0)
        graph.streamTo(graphDiv)

$(document).ready ->
    init()
