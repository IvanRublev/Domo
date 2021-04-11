defmodule Domo.TaggedTuple do
  @moduledoc """
  Functions that works on tagged tuples for domain modelling
  """

  defmacro __using__(_opts) do
    quote do
      require unquote(__MODULE__)

      import unquote(__MODULE__),
        only: [
          ---: 2
        ]

      alias unquote(__MODULE__)
    end
  end

  @doc """
  Defines a tagged tuple inline.

  The operator is right-associative. It adds a tag or a chain of tags to a value.

  ## Examples

      iex> use Domo.TaggedTuple
      ...> Tag --- 12
      {Tag, 12}

      iex> use Domo.TaggedTuple
      ...> A --- Tag --- Chain --- 12
      {A, {Tag, {Chain, 12}}}

  """
  # credo:disable-for-next-line
  defmacro tag --- value do
    quote do
      {unquote(tag), unquote(value)}
    end
  end

  @doc """
  Returns a tagged tuple by joining the tag chain with the value.

  The macro supports up to 6 links in the tag chain.

  ## Example

      iex> use Domo.TaggedTuple
      ...> tag(2.5, SomeTag)
      {SomeTag, 2.5}

      iex> use Domo.TaggedTuple
      ...> tag(7, {A, {Tag, Chain}})
      {A, {Tag, {Chain, 7}}}
  """
  defmacro tag(value, tag_chain) do
    quote do
      unquote(__MODULE__).do_tag(unquote(value), unquote(tag_chain))
    end
  end

  @doc false
  defguard not_tuple(t1)
           when not is_tuple(t1)

  @doc false
  defguard not_tuple(t2, t1)
           when not is_tuple(t2) and not is_tuple(t1)

  @doc false
  defguard not_tuple(t3, t2, t1)
           when not is_tuple(t3) and not is_tuple(t2) and not is_tuple(t1)

  @doc false
  defguard not_tuple(t4, t3, t2, t1)
           when not is_tuple(t4) and not is_tuple(t3) and not is_tuple(t2) and not is_tuple(t1)

  @doc false
  defguard not_tuple(t5, t4, t3, t2, t1)
           when not is_tuple(t5) and not is_tuple(t4) and not is_tuple(t3) and not is_tuple(t2) and
                  not is_tuple(t1)

  @doc false
  defguard not_tuple(t6, t5, t4, t3, t2, t1)
           when not is_tuple(t6) and not is_tuple(t5) and not is_tuple(t4) and not is_tuple(t3) and
                  not is_tuple(t2) and not is_tuple(t1)

  @doc false
  def do_tag(v, t1) when not_tuple(t1),
    do: {t1, v}

  def do_tag(v, {t2, t1}) when not_tuple(t2, t1),
    do: {t2, {t1, v}}

  def do_tag(v, {t3, {t2, t1}}) when not_tuple(t3, t2, t1),
    do: {t3, {t2, {t1, v}}}

  def do_tag(v, {t4, {t3, {t2, t1}}}) when not_tuple(t4, t3, t2, t1),
    do: {t4, {t3, {t2, {t1, v}}}}

  def do_tag(v, {t5, {t4, {t3, {t2, t1}}}}) when not_tuple(t5, t4, t3, t2, t1),
    do: {t5, {t4, {t3, {t2, {t1, v}}}}}

  def do_tag(v, {t6, {t5, {t4, {t3, {t2, t1}}}}}) when not_tuple(t6, t5, t4, t3, t2, t1),
    do: {t6, {t5, {t4, {t3, {t2, {t1, v}}}}}}

  @doc """
  Returns the value from the tagged tuple when the tag chain matches.

  Raises `ArgumentError` exception if the passed tag chain is not one that
  is in the tagged tuple. Supports up to 6 links in the tag chain.

  ## Examples

      iex> use Domo.TaggedTuple
      ...> value = {A, {Tag, {Chain, 2}}}
      ...> untag!(value, {A, {Tag, Chain}})
      2

      iex> use Domo.TaggedTuple
      ...> value = {Other, {Stuff, 2}}
      ...> untag!(value, {A, {Tag, Chain}})
      ** (ArgumentError) Tag chain {A, {Tag, Chain}} doesn't match one in the tagged tuple {Other, {Stuff, 2}}.

  """
  defmacro untag!(tagged_tuple, tag_chain) do
    quote do
      unquote(__MODULE__).do_untag!(unquote(tagged_tuple), unquote(tag_chain))
    end
  end

  @doc false
  def do_untag!({t1, v}, t1)
      when not_tuple(t1),
      do: v

  def do_untag!({t2, {t1, v}}, {t2, t1})
      when not_tuple(t2, t1),
      do: v

  def do_untag!({t3, {t2, {t1, v}}}, {t3, {t2, t1}})
      when not_tuple(t3, t2, t1),
      do: v

  def do_untag!({t4, {t3, {t2, {t1, v}}}}, {t4, {t3, {t2, t1}}})
      when not_tuple(t4, t3, t2, t1),
      do: v

  def do_untag!({t5, {t4, {t3, {t2, {t1, v}}}}}, {t5, {t4, {t3, {t2, t1}}}})
      when not_tuple(t5, t4, t3, t2, t1),
      do: v

  def do_untag!({t6, {t5, {t4, {t3, {t2, {t1, v}}}}}}, {t6, {t5, {t4, {t3, {t2, t1}}}}})
      when not_tuple(t6, t5, t4, t3, t2, t1),
      do: v

  def do_untag!(tt, c),
    do:
      Kernel.raise(
        ArgumentError,
        "Tag chain #{inspect(c)} doesn't match one in the tagged tuple #{inspect(tt)}."
      )
end
