(function(){

  window.rum !== false && (function(window, document, location){

    var logjamPageAction    = document.querySelector("meta[name^=logjam-action]"),
        logjamPageRequestId = document.querySelector("meta[name^=logjam-request-id]"),
        monitoringCollector = document.querySelector("meta[name^=logjam-timings-collector]");

    if ( !(monitoringCollector && logjamPageAction && logjamPageAction) )
      return;

    monitoringCollector = monitoringCollector.content + "/logjam/";
    logjamPageAction    = logjamPageAction.content;
    logjamPageRequestId = logjamPageRequestId.content;

    var monitoringMeasures,
        _toQuery = function(obj){
          obj._ = new Date().getTime();
          return Object.keys(obj).map(function(k) {
            return encodeURIComponent(k) + "=" + encodeURIComponent(obj[k]);
          }).join("&");
        };

    Monitoring = function(){
      if( window.addEventListener && window.performance ) {
        this.setXMLHttpRequestHook();
        this.getStaticMetrics();

        (document.readyState !== 'loading') ? this.getDomInformation() : document.addEventListener("DOMContentLoaded", this.getDomInformation, false);
        (document.readyState === 'complete') ? this.getPerformanceData() : window.addEventListener("load", this.getPerformanceData, false);

      } else {
        window.performance = { navigation: {}, timing: {} };
        this.getStaticMetrics();
        this.getEmptyPerformanceData();
      }

      return this;
    };

    Monitoring.prototype = {

      getStaticMetrics: function(){
        monitoringMeasures = {
          logjam_action:     logjamPageAction,
          logjam_request_id: logjamPageRequestId,
          url:               location.pathname,
          screen_height:     screen.height,
          screen_width:      screen.width,
          redirect_count:    performance.navigation.redirectCount,
          v:                 1
        };
      },

      getDomInformation: function(){
          monitoringMeasures.html_nodes   = document.getElementsByTagName("*").length;
          monitoringMeasures.script_nodes = document.scripts.length;
          monitoringMeasures.style_nodes  = document.styleSheets.length;
      },

      getEmptyPerformanceData: function() {
        this.getPerformanceData();
      },

      getPerformanceData: function() {
        setTimeout(function(){
          var timing     = performance.timing,
              fetchStart = timing.fetchStart,
              rts    = [];

          [
            'navigationStart',
            'fetchStart',
            'domainLookupStart',
            'domainLookupEnd',
            'connectStart',
            'connectEnd',
            'requestStart',
            'responseStart',
            'responseEnd',
            'domLoading',
            'domInteractive',
            'domContentLoadedEventStart',
            'domContentLoadedEventEnd',
            'domComplete',
            'loadEventStart',
            'loadEventEnd'
          ].forEach(function(key){
            rts.push(timing[key] || 0);
          });

          monitoringMeasures.rts = rts;

          var tracking_url = monitoringCollector+"page?"+_toQuery(monitoringMeasures);

          if (typeof navigator.sendBeacon === "function")
            navigator.sendBeacon(tracking_url);
          else
            (new Image()).src = tracking_url;
        }, 20);
      },

      setXMLHttpRequestHook: function(){
        var originalXMLHttpRequest = XMLHttpRequest;
        window.XMLHttpRequest = function() {
          var request = new originalXMLHttpRequest(),
              monitoringOpen = request.open,
              monitoringStart,
              monitoringUrl;

          request.open = function(method, url, async) {
            monitoringUrl = url;
            monitoringOpen.call(this, method, url, async);
          };

          request.addEventListener("readystatechange", function() {
            var logjamRequestId, logjamRequestAction;

            if (request.readyState == 1) {
              monitoringStart = +new Date();
            }
            if (request.readyState == 4) {
              try {
                logjamRequestId = (request.getResponseHeader("X-Logjam-Request-Id") || false);
                logjamRequestAction = (request.getResponseHeader("X-Logjam-Request-Action") || false);
              } catch(e) {
                logjamRequestId = logjamRequestAction = false;
              }

              if(logjamRequestId && logjamRequestAction) {
                var requestData = {
                  logjam_caller_id:     logjamPageRequestId,
                  logjam_caller_action: logjamPageAction,
                  logjam_request_id:    logjamRequestId,
                  logjam_action:        logjamRequestAction,
                  rts:                  [monitoringStart, +new Date()],
                  url:                  monitoringUrl.replace((location.protocol + "//" + location.host) , "").replace("//", "/").split("?")[0],
                  v:                    1
                };
                var tracking_url = monitoringCollector+"ajax?"+_toQuery(requestData);
                if (typeof navigator.sendBeacon === "function")
                  navigator.sendBeacon(tracking_url);
                else
                  (new Image()).src = tracking_url;
              }
            }
          }, false);
          return request;
        };
      }
    };
    new Monitoring();

  })(window, document, location);
})();
