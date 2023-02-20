function log (...args) {
    for (let i = 0; i < args.length; i++) {
        console.log(args[i]);
    }
}

module.exports.log = log;