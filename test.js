const db = require('./database/db.js');
const log = require('./alias.js').log;

var start = async function() {
    await db.connect();
    await db.insertUser({name: "Petya", user_id: "xx3", biota: {code: 'fu'}});

    let search_result = await db.getUser("xx2");
    log(search_result);
};

start();