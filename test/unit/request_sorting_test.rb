require_relative "../test_helper"

class RequestSortingTest < ActiveSupport::TestCase
  def test_sorting
    skip "this test fails for mongo 3.5 and onwards"
    db_name = "logjam-sorting-test"
    client = Mongo::Client.new(%w(localhost:27017))
    db = client.use(db_name).database
    collection = db["requests"]
    collection.drop
    collection.indexes.create_one({ "metrics.n" => 1, "metrics.v" => -1 })
    documents = [
      {
        "page" => 1,
        "metrics" => [
          {"n" => "a", "v" => 1},
          {"n" => "b", "v" => 5}
        ]
      },
      {
        "page" => 1,
        "metrics" => [
          {"n" => "a", "v" => 2},
          {"n" => "b", "v" => 4}
        ]
      }
    ]
    collection.insert_many(documents)
    requests = collection.find({"metrics.n" => "b"}).sort({"metrics.n" => 1, "metrics.v": -1}).to_a
    requests.inject(10) do |last, doc|
      puts doc.inspect
      v = get_value(doc, "b")
      assert_operator(last, :>=, v)
      v
    end
  end

  private

  def get_value(document, metric)
    document["metrics"].each do |h|
      return h["v"] if h["n"] == metric
    end
    raise "metric #{metric} not found in #{document}"
  end

end
