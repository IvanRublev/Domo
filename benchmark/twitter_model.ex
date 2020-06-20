defmodule Benchmark.Tweet do
  @moduledoc """
  Tweet object with some redactions.
  ## Reference
  [Tweet object](https://developer.twitter.com/en/docs/tweets/data-dictionary/overview/tweet-object)
  """

  use Domo

  typedstruct do
    field :created_at, String.t()
    field :favorite_count, non_neg_integer | nil
    field :favorited, boolean | nil
    field :id, pos_integer
    field :id_str, String.t()
    field :in_reply_to_screen_name, String.t() | nil
    field :in_reply_to_status_id, pos_integer | nil
    field :in_reply_to_status_id_str, String.t() | nil
    field :in_reply_to_user_id, pos_integer | nil
    field :in_reply_to_user_id_str, String.t() | nil
    field :is_quote_status, boolean
    field :lang, String.t() | nil
    field :possibly_sensitive, boolean | nil
    field :retweet_count, non_neg_integer
    field :retweeted, boolean
    field :source, String.t()
    field :text, String.t()
    field :truncated, boolean
    field :user, Benchmark.Tweet.User.t() | nil
  end
end

defmodule Benchmark.Tweet.User do
  @moduledoc """
  User object with some redactions.
  ## Reference
  [User object](https://developer.twitter.com/en/docs/tweets/data-dictionary/overview/user-object)
  """

  use Domo

  typedstruct do
    field :created_at, String.t()
    field :default_profile, boolean
    field :default_profile_image, boolean
    field :description, String.t() | nil
    field :favourites_count, non_neg_integer
    field :followers_count, non_neg_integer
    field :friends_count, non_neg_integer
    field :id, pos_integer
    field :id_str, String.t()
    field :listed_count, non_neg_integer
    field :location, String.t() | nil
    field :name, String.t()
    field :profile_banner_url, String.t()
    field :profile_image_url_https, String.t()
    field :protected, boolean
    field :screen_name, String.t()
    field :statuses_count, non_neg_integer
    field :url, String.t() | nil
    field :verified, boolean
  end
end
