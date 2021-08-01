// We need to import the CSS so that webpack will load it.
// The MiniCssExtractPlugin is used to separate it out into
// its own CSS file.
import "../css/app.scss"

// webpack automatically bundles all modules in your
// entry points. Those entry points can be configured
// in "webpack.config.js".
//
// Import deps with the dep name or local files with a relative path, for example:
//
//     import {Socket} from "phoenix"
//     import socket from "./socket"
//
import "phoenix_html"
import {Socket} from "phoenix"
import NProgress from "nprogress"
import {LiveSocket} from "phoenix_live_view"
import UIkit from 'uikit';
import Icons from 'uikit/dist/js/uikit-icons';
import Chart from 'chart.js/auto';
import 'chartjs-adapter-moment';
import moment from "moment"

UIkit.use(Icons);

let Hooks = {};

Hooks.TradesChart = {
    mounted() {
        let trades =
            JSON.parse(this.el.dataset.trades)
            .map((trade) => {
                trade.executed_at = new Date(Date.parse(trade.executed_at));
                return trade;
            })
            .reverse();

        let chart = new Chart(this.el, {
            type: 'line',
            data: {
                datasets: [{
                    label: "Price",
                    data: trades,
                    parsing: {
                        xAxisKey: "executed_at",
                        yAxisKey: "price"
                    }
                }]
            },
            options: {
                scales: {
                    x: {
                        type: "time",
                        min: moment().subtract(10, "minutes"),
                        ticks: {
                            stepSize: 1
                        },
                        time: {
                            unit: 'second',
                            stepSize: 5,
                            round: true
                        }
                    }
                }
            }
        });

        this.handleEvent("trades", (event) => {
            event.trades.forEach((trade) => {
                chart.data.datasets.forEach((dataset) => {
                    trade.executed_at = new Date(Date.parse(trade.executed_at))
                    dataset.data.push(trade)
                })
            })
            chart.update();
        });
    },
};

let csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
let liveSocket = new LiveSocket("/live", Socket, {hooks: Hooks, params: {_csrf_token: csrfToken}})

// Show progress bar on live navigation and form submits
window.addEventListener("phx:page-loading-start", info => NProgress.start())
window.addEventListener("phx:page-loading-stop", info => NProgress.done())

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket