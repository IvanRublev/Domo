defmodule Benchmark.Tweet do
  @moduledoc """
  Tweet object with some redactions.

  ## Reference

  [Tweet object](https://developer.twitter.com/en/docs/tweets/data-dictionary/overview/tweet-object)
  """

  use Domo

  defstruct [
    :created_at,
    :favorite_count,
    :favorited,
    :id,
    :id_str,
    :in_reply_to_screen_name,
    :in_reply_to_status_id,
    :in_reply_to_status_id_str,
    :in_reply_to_user_id,
    :in_reply_to_user_id_str,
    :is_quote_status,
    :lang,
    :possibly_sensitive,
    :retweet_count,
    :retweeted,
    :source,
    :text,
    :truncated,
    :user
  ]

  @type tweet_id :: pos_integer
  precond tweet_id: &(36_183_115_464_704 <= &1 and &1 <= 1_274_036_183_115_464_704)

  @type t :: %__MODULE__{
          created_at: String.t(),
          favorite_count: non_neg_integer | nil,
          favorited: boolean | nil,
          id: tweet_id,
          id_str: String.t(),
          in_reply_to_screen_name: String.t() | nil,
          in_reply_to_status_id: pos_integer | nil,
          in_reply_to_status_id_str: String.t() | nil,
          in_reply_to_user_id: pos_integer | nil,
          in_reply_to_user_id_str: String.t() | nil,
          is_quote_status: boolean,
          lang: String.t() | nil,
          possibly_sensitive: boolean | nil,
          retweet_count: non_neg_integer,
          retweeted: boolean,
          source: String.t(),
          text: String.t(),
          truncated: boolean,
          user: Benchmark.Tweet.User.t() | nil
        }
end

defmodule Benchmark.Tweet.User do
  @moduledoc """
  User object with some redactions.

  ## Reference

  [User object](https://developer.twitter.com/en/docs/tweets/data-dictionary/overview/user-object)
  """

  use Domo

  defstruct [
    :created_at,
    :default_profile,
    :default_profile_image,
    :description,
    :favourites_count,
    :followers_count,
    :friends_count,
    :id,
    :id_str,
    :listed_count,
    :location,
    :name,
    :profile_banner_url,
    :profile_image_url_https,
    :protected,
    :screen_name,
    :statuses_count,
    :url,
    :verified
  ]

  @type t :: %__MODULE__{
          created_at: String.t(),
          default_profile: boolean,
          default_profile_image: boolean,
          description: String.t() | nil,
          favourites_count: non_neg_integer,
          followers_count: non_neg_integer,
          friends_count: non_neg_integer,
          id: pos_integer,
          id_str: String.t(),
          listed_count: non_neg_integer,
          location: String.t() | nil,
          name: String.t(),
          profile_banner_url: String.t(),
          profile_image_url_https: String.t(),
          protected: boolean,
          screen_name: String.t(),
          statuses_count: non_neg_integer,
          url: String.t() | nil,
          verified: boolean
        }
end
