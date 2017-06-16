/*global cordova, module*/

module.exports = {
  initSong: function(url, successCallback, errorCallback) {
    cordova.exec(successCallback, errorCallback, "Hello", "initSong", [url]);
  },
  play: function(successCallback, errorCallback) {
    cordova.exec(successCallback, errorCallback, "Hello", "play");
  },
  pause: function(successCallback, errorCallback) {
    cordova.exec(successCallback, errorCallback, "Hello", "pause");
  },
  receiveRemoteEvent: function(event) {
    var ev = document.createEvent('HTMLEvents');
    ev.remoteEvent = event;
    ev.initEvent('remote-event', true, true, arguments);
    document.dispatchEvent(ev);
  }
};
