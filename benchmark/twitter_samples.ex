defmodule Benchmark.Samples do
  @moduledoc "Module to generate maps for Twitter model"

  def tweet_map do
    StreamData.fixed_map(%{
      created_at: StreamData.string(:alphanumeric, max_length: 20),
      favorite_count:
        StreamData.one_of([StreamData.integer(1..100), StreamData.member_of([nil])]),
      favorited: StreamData.one_of([StreamData.boolean(), StreamData.member_of([nil])]),
      id: StreamData.integer(36_183_115_464_704..1_274_036_183_115_464_704),
      id_str: StreamData.string(:alphanumeric, max_length: 20),
      in_reply_to_screen_name:
        StreamData.one_of([
          StreamData.string(:alphanumeric, max_length: 20),
          StreamData.member_of([nil])
        ]),
      in_reply_to_status_id:
        StreamData.one_of([StreamData.integer(1..7000), StreamData.member_of([nil])]),
      in_reply_to_status_id_str:
        StreamData.one_of([
          StreamData.string(:alphanumeric, max_length: 20),
          StreamData.member_of([nil])
        ]),
      in_reply_to_user_id:
        StreamData.one_of([StreamData.integer(1..7000), StreamData.member_of([nil])]),
      in_reply_to_user_id_str:
        StreamData.one_of([
          StreamData.string(:alphanumeric, max_length: 20),
          StreamData.member_of([nil])
        ]),
      is_quote_status: StreamData.boolean(),
      lang:
        StreamData.one_of([
          StreamData.string(:alphanumeric, max_length: 3),
          StreamData.member_of([nil])
        ]),
      possibly_sensitive: StreamData.one_of([StreamData.boolean(), StreamData.member_of([nil])]),
      retweet_count: StreamData.integer(1..100),
      retweeted: StreamData.boolean(),
      source: StreamData.string(:alphanumeric, max_length: 85),
      text: StreamData.string(:alphanumeric, max_length: 140),
      truncated: StreamData.boolean()
    })
  end

  def user_map do
    StreamData.fixed_map(%{
      created_at: StreamData.string(:alphanumeric, max_length: 20),
      default_profile: StreamData.boolean(),
      default_profile_image: StreamData.boolean(),
      description:
        StreamData.one_of([
          StreamData.string(:alphanumeric, max_length: 112),
          StreamData.member_of([nil])
        ]),
      favourites_count: StreamData.integer(1..7000),
      followers_count: StreamData.integer(1..7000),
      friends_count: StreamData.integer(1..30),
      id: StreamData.integer(1_000_000_000..3_333_164_561),
      id_str: StreamData.string(:ascii, length: 10),
      listed_count: StreamData.integer(1..300),
      location:
        StreamData.one_of([
          StreamData.string(:alphanumeric, max_length: 15),
          StreamData.member_of([nil])
        ]),
      name: StreamData.string(:alphanumeric, max_length: 11),
      profile_banner_url: StreamData.string(:alphanumeric, max_length: 64),
      profile_image_url_https: StreamData.string(:alphanumeric, max_length: 82),
      protected: StreamData.boolean(),
      screen_name: StreamData.string(:alphanumeric, max_length: 14),
      statuses_count: StreamData.integer(1..4000),
      url:
        StreamData.one_of([
          StreamData.string(:alphanumeric, max_length: 25),
          StreamData.member_of([nil])
        ]),
      verified: StreamData.boolean()
    })
  end
end
