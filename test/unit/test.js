use test;
db.requests.drop();
db.requests.createIndex({ "metrics.n" : 1, "metrics.v" : -1 });
db.requests.insert({
  "page" : 1,
  "metrics" : [
    {"n" : "a", "v" : 10},
    {"n" : "b", "v" : 5}
  ]
});
db.requests.insert({
  "page" : 2,
  "metrics" : [
    {"n" : "a", "v": 20},
    {"n" : "b", "v": 4}
  ]
});
db.requests.find({"metrics.n":"b"}).sort({"metrics.n":1,"metrics.v":-1});
