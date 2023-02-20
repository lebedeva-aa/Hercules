const express = require('express');
const db = require('./database/db.js');
const app = express();
var bodyParser = require('body-parser');
const log = require("./alias.js").log;
const process_biota = 

var resError = function (res, err_msg = "Unknown error", status = 400) {
    res.status = status;
    res.send({err : err_msg});
};

app.use(bodyParser());

app.get("/start", async function (req, res) {
    if (!req.body) {
        resError(res, "No body in request", 400);
        return;
    }
    if (await db.getUser(req.body.user_id) != null) {
        log(req.body);
        res.status = 200;
        res.send({ user_id : req.body.user_id, status: 200 });
        return;
    } else {
        let insertion_result = db.insertUser({
            user_id: req.body.user_id,
            name: "no_name",
            biota: { name : "name" }
        });
        insertion_result.catch((reason) => {
            res.status = 400;
            res.send({ err: reason });
            return;
        });
        insertion_result.then((result) => {
            res.status = 200;
            res.send({ user_id: result.user_id, status: 200, server_msg: "New user created" });
            return;
        });
    }
    resError(res, "Unknown error");
});

app.get("/process/image", function (req, res) {
    if (!req.body) {
        resError(res, "No body in request", 400);
        return;
    }
    if (!req.body.image) {
        resError(res,"No image file in request", 400);
        return;
    }

    //TODO image processing code
    res.status(200);
    res.send({
        user_id: req.body.user_id,
        result: [
            {food_id: 0},
            {food_id: 1},
            {food_id: 2}
        ],
        server_msg: "Image processing not working yet, that's sample result"
    });
    return;

    resError(res);
    return;
});

app.get("/process/biota", function (req, res) {

});

db.connect(() => {
        app.listen(4000, function () {
            log("Server started at port " + 4000);
        });
    }
);