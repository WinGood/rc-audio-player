/*global cordova, module*/

module.exports = {
    initSong: function (url, successCallback, errorCallback) {
        cordova.exec(successCallback, errorCallback, "Hello", "initSong", [url]);
    },
    play: function () {
        cordova.exec(successCallback, errorCallback, "Hello", "play");
    },
    pause: function () {
        cordova.exec(successCallback, errorCallback, "Hello", "pause");
    }
};
