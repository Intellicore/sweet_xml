defmodule SweetXpath do
  defstruct path: ".", is_value: true, is_list: false, is_keyword: false, is_optional: false, cast_to: false
end

defmodule SweetXml do
  @moduledoc ~S"""
  `SweetXml` is a thin wrapper around `:xmerl`. It allows you to convert a
  string or xmlElement record as defined in `:xmerl` to an elixir value such
  as `map`, `list`, `char_list`, or any combination of these.

  For normal sized documents, `SweetXml` primarily exposes 3 functions

    * `SweetXml.xpath/2` - return a value based on the xpath expression
    * `SweetXml.xpath/3` - similar to above but allowing nesting of mapping
    * `SweetXml.xmap/2` - return a map with keywords mapped to values returned
      from xpath

  For something larger, `SweetXml` mainly exposes 1 function

    * `SweetXml.stream_tags/3` - stream a given tag or a list of tags, and
      optionally "discard" some dom elements in order to free memory during
      streaming for big files which cannot fit entirely in memory

  ## Examples

  Simple Xpath

      iex> import SweetXml
      iex> doc = "<h1><a>Some linked title</a></h1>"
      iex> doc |> xpath(~x"//a/text()")
      'Some linked title'

  Nested Mapping

      iex> import SweetXml
      iex> doc = "<body><header><p>Message</p><ul><li>One</li><li><a>Two</a></li></ul></header></body>"
      iex> doc |> xpath(~x"//header", message: ~x"./p/text()", a_in_li: ~x".//li/a/text()"l)
      %{a_in_li: ['Two'], message: 'Message'}

  Streaming

      iex> import SweetXml
      iex> doc = ["<ul><li>l1</li><li>l2", "</li><li>l3</li></ul>"]
      iex> SweetXml.stream_tags(doc, :li)
      ...> |> Stream.map(fn {:li, doc} ->
      ...>      doc |> SweetXml.xpath(~x"./text()")
      ...>    end)
      ...> |> Enum.to_list
      ['l1', 'l2', 'l3']

  For more examples please see help for each individual functions

  ## The ~x Sigil

  Notice in the above examples, we used the expression `~x"//a/text()"` to
  define the path. The reason is it allows us to more precisely specify what
  is being returned.

    * `~x"//some/path"`

      without any modifiers, `xpath/2` will return the value of the entity if
      the entity is of type `xmlText`, `xmlAttribute`, `xmlPI`, `xmlComment`
      as defined in `:xmerl`

    * `~x"//some/path"e`

      `e` stands for (e)ntity. This forces `xpath/2` to return the entity with
      which you can further chain your `xpath/2` call

    * `~x"//some/path"l`

      'l' stands for (l)ist. This forces `xpath/2` to return a list. Without
      `l`, `xpath/2` will only return the first element of the match

    * `~x"//some/path"el` - mix of the above

    * `~x"//some/path"k`

      'k' stands for (K)eyword. This forces `xpath/2` to return a Keyword instead of a Map.

    * `~x"//some/path"s`

      's' stands for (s)tring. This forces `xpath/2` to return the value as
      string instead of a char list.

    * `x"//some/path"o`

      'o' stands for (O)ptional. This allows the path to not exist, and will return nil.

    * `~x"//some/path"sl` - string list.

  Notice also in the examples section, we always import SweetXml first. This
  makes `x_sigil` available in the current scope. Without it, instead of using
  `~x`, you can do the following

      iex> doc = "<h1><a>Some linked title</a></h1>"
      iex> doc |> SweetXml.xpath(%SweetXpath{path: '//a/text()', is_value: true, cast_to: false, is_list: false, is_keyword: false})
      'Some linked title'

  Note the use of char_list in the path definition.
  """

  require Record
  Record.defrecord :xmlDecl, Record.extract(:xmlDecl, from_lib: "xmerl/include/xmerl.hrl")
  Record.defrecord :xmlAttribute, Record.extract(:xmlAttribute, from_lib: "xmerl/include/xmerl.hrl")
  Record.defrecord :xmlNamespace, Record.extract(:xmlNamespace, from_lib: "xmerl/include/xmerl.hrl")
  Record.defrecord :xmlNsNode, Record.extract(:xmlNsNode, from_lib: "xmerl/include/xmerl.hrl")
  Record.defrecord :xmlElement, Record.extract(:xmlElement, from_lib: "xmerl/include/xmerl.hrl")
  Record.defrecord :xmlText, Record.extract(:xmlText, from_lib: "xmerl/include/xmerl.hrl")
  Record.defrecord :xmlComment, Record.extract(:xmlComment, from_lib: "xmerl/include/xmerl.hrl")
  Record.defrecord :xmlPI, Record.extract(:xmlPI, from_lib: "xmerl/include/xmerl.hrl")
  Record.defrecord :xmlDocument, Record.extract(:xmlDocument, from_lib: "xmerl/include/xmerl.hrl")
  Record.defrecord :xmlObj, Record.extract(:xmlObj, from_lib: "xmerl/include/xmerl.hrl")


  @doc ~s"""
  `sigil_x/2` simply returns a `SweetXpath` struct, with modifiers converted to
  boolean fields

      iex> SweetXml.sigil_x("//some/path", 'e')
      %SweetXpath{path: '//some/path', is_value: false, cast_to: false, is_list: false, is_keyword: false}

  or you can simply import and use the `~x` expression

      iex> import SweetXml
      iex> ~x"//some/path"e
      %SweetXpath{path: '//some/path', is_value: false, cast_to: false, is_list: false, is_keyword: false}

  Valid modifiers are `e`, `s`, `l` and `k`. Below is the full explanation

    * `~x"//some/path"`

      without any modifiers, `xpath/2` will return the value of the entity if
      the entity is of type `xmlText`, `xmlAttribute`, `xmlPI`, `xmlComment`
      as defined in `:xmerl`

    * `~x"//some/path"e`

      `e` stands for (e)ntity. This forces `xpath/2` to return the entity with
      which you can further chain your `xpath/2` call

    * `~x"//some/path"l`

      'l' stands for (l)ist. This forces `xpath/2` to return a list. Without
      `l`, `xpath/2` will only return the first element of the match

    * `~x"//some/path"el` - mix of the above

    * `~x"//some/path"k`

      'k' stands for (K)eyword. This forces `xpath/2` to return a Keyword instead of a Map.

    * `~x"//some/path"s`

      's' stands for (s)tring. This forces `xpath/2` to return the value as
      string instead of a char list.

    * `x"//some/path"o`

      'o' stands for (O)ptional. This allows the path to not exist, and will return nil.

    * `~x"//some/path"sl` - string list.

    * `~x"//some/path"i`

      'i' stands for (i)nteger. This forces `xpath/2` to return the value as
      integer instead of a char list.

    * `~x"//some/path"il` - integer list
  """
  def sigil_x(path, modifiers \\ '') do
    %SweetXpath{
      path: String.to_char_list(path),
      is_value: not ?e in modifiers,
      is_list: ?l in modifiers,
      is_keyword: ?k in modifiers,
      is_optional: ?o in modifiers,
      cast_to: cond do
        ?s in modifiers -> :string
        ?i in modifiers -> :integer
        :otherwise -> false
      end
    }
  end

  @doc """
  `doc` can be

  - a byte list (iodata)
  - a binary
  - any enumerable of binaries (for instance `File.stream!/3` result)

  `options` are `xmerl` options described here [http://www.erlang.org/doc/man/xmerl_scan.html](http://www.erlang.org/doc/man/xmerl_scan.html),
  see [the erlang tutorial](http://www.erlang.org/doc/apps/xmerl/xmerl_examples.html) for usage.

  When `doc` is an enumerable, the `:cont_fun` option cannot be given.

  Return an `xmlElement` record
  """
  def parse(doc), do: parse(doc, [])
  def parse(doc, options) when is_binary(doc) do
    doc |> :erlang.binary_to_list |> parse(options)
  end
  def parse([c | _] = doc, options) when is_integer(c) do
    {parsed_doc, _} = :xmerl_scan.string(doc, options)
    parsed_doc
  end
  def parse(doc_enum, options) do
    {parsed_doc, _} = :xmerl_scan.string('', options ++ continuation_opts(doc_enum))
    parsed_doc
  end

  @doc """
  Most common usage of streaming: stream a given tag or a list of tags, and
  optionally "discard" some dom elements in order to free memory during streaming
  for big files which cannot fit entirely in memory.

  Note that each matched tag produces it's own tree. If a given tag appears in
  the discarded options, it is ignored.

  - `doc` is an enumerable, data will be pulled during the result stream
    enumeration. e.g. `File.stream!("some_file.xml")`
  - `tags` is an atom or a list of atoms you want to extract. Each stream element
    will be `{:tagname, xmlelem}`. e.g. :li, :header
  - `options[:discard]` is the list of tag which will be discarded:
     not added to its parent DOM.

  Examples:

      iex> import SweetXml
      iex> doc = ["<ul><li>l1</li><li>l2", "</li><li>l3</li></ul>"]
      iex> SweetXml.stream_tags(doc, :li, discard: [:li])
      ...> |> Stream.map(fn {:li, doc} -> doc |> SweetXml.xpath(~x"./text()") end)
      ...> |> Enum.to_list
      ['l1', 'l2', 'l3']
      iex> SweetXml.stream_tags(doc, [:ul, :li])
      ...> |> Stream.map(fn {_, doc} -> doc |> SweetXml.xpath(~x"./text()") end)
      ...> |> Enum.to_list
      ['l1', 'l2', 'l3', nil]


  Becareful if you set `options[:discard]`. If any of the discarded tags is nested
  inside a kept tag, you will not be able to access them.

  Examples:

      iex> import SweetXml
      iex> doc = ["<header>", "<title>XML</title", "><header><title>Nested</title></header></header>"]
      iex> SweetXml.stream_tags(doc, :header)
      ...> |> Stream.map(fn {_, doc} -> SweetXml.xpath(doc, ~x".//title/text()") end)
      ...> |> Enum.to_list
      ['Nested', 'XML']
      iex> SweetXml.stream_tags(doc, :header, discard: [:title])
      ...> |> Stream.map(fn {_, doc} -> SweetXml.xpath(doc, ~x"./title/text()") end)
      ...> |> Enum.to_list
      [nil, nil]

  """
  def stream_tags(doc, tags, options \\ []) do
    tags = if is_atom(tags), do: [tags], else: tags

    {discard_tags, xmerl_options} = if options[:discard] do
      {options[:discard], Keyword.delete(options, :discard)}
    else
      {[], options}
    end

    doc |> stream(fn emit ->
      [
        hook_fun: fn
          entity, xstate when Record.is_record(entity, :xmlElement) ->
            name = xmlElement(entity, :name)
            if length(tags) == 0 or name in tags do
              emit.({name, entity})
            end
            {entity, xstate}
          entity, xstate ->
            {entity, xstate}
        end,
        acc_fun: fn
          entity, acc, xstate when Record.is_record(entity, :xmlElement) ->
            if xmlElement(entity, :name) in discard_tags do
              {acc, xstate}
            else
              {[entity | acc], xstate}
            end
          entity, acc, xstate ->
            {[entity | acc], xstate}
        end
      ] ++ xmerl_options
    end)
  end

  @doc """
  Create an element stream from a xml `doc`.

  This is a lower level API compared to `SweetXml.stream_tags`. You can use
  the `options_callback` argument to get fine control of what data to be streamed.

  - `doc` is an enumerable, data will be pulled during the result stream
    enumeration. e.g. `File.stream!("some_file.xml")`
  - `options_callback` is an anonymous function `fn emit -> xmerl_opts` use it to
    define your :xmerl callbacks and put data into the stream using
    `emit.(elem)` in the callbacks.

  For example, here you define a stream of all `xmlElement` :

      iex> import Record
      iex> doc = ["<h1", "><a>Som", "e linked title</a><a>other</a></h1>"]
      iex> SweetXml.stream(doc, fn emit ->
      ...>   [
      ...>     hook_fun: fn
      ...>       entity, xstate when is_record(entity, :xmlElement)->
      ...>         emit.(entity)
      ...>         {entity, xstate}
      ...>       entity, xstate ->
      ...>         {entity,xstate}
      ...>     end
      ...>   ]
      ...> end) |> Enum.count
      3
  """
  def stream(doc, options_callback) when is_binary(doc) do
    stream([doc], options_callback)
  end
  def stream([c | _] = doc, options_callback) when is_integer(c) do
    stream([IO.iodata_to_binary(doc)], options_callback)
  end
  def stream(doc, options_callback) do
    Stream.resource fn ->
      {parent, ref} = waiter = {self, make_ref}
      opts = options_callback.(fn e -> send(parent, {:event, ref, e}) end)
      pid = spawn fn -> :xmerl_scan.string('', opts ++ continuation_opts(doc, waiter)) end
      {ref, pid, Process.monitor(pid)}
    end, fn {ref, pid, monref} = acc ->
      receive do
        {:DOWN, ^monref, _, _, _} ->
          {:halt, :parse_ended} ## !!! maybe do something when reason !== :normal
        {:event, ^ref, event} ->
          {[event], acc}
        {:wait, ^ref} ->
          send(pid, {:continue, ref})
          {[], acc}
      end
    end, fn
      :parse_ended -> :ok
      {ref, pid, monref} ->
        Process.demonitor(monref)
        flush_halt(pid, ref)
    end
  end

  @doc ~S"""
  `xpath` allows you to query an xml document with xpath.

  The second argument to xpath is a `SweetXpath` struct. The optional third
  argument is a keyword list, such that the value of each keyword is also
  either a `SweetXpath` or a list with head being a `SweetXpath` and tail being
  another keyword list exactly like before. Please see examples below for better
  understanding.

  ## Examples

  Simple

      iex> import SweetXml
      iex> doc = "<h1><a>Some linked title</a></h1>"
      iex> doc |> xpath(~x"//a/text()")
      'Some linked title'

  With optional mapping

      iex> import SweetXml
      iex> doc = "<body><header><p>Message</p><ul><li>One</li><li><a>Two</a></li></ul></header></body>"
      iex> doc |> xpath(~x"//header", message: ~x"./p/text()", a_in_li: ~x".//li/a/text()"l)
      %{a_in_li: ['Two'], message: 'Message'}

  With optional mapping and nesting

      iex> import SweetXml
      iex> doc = "<body><header><p>Message</p><ul><li>One</li><li><a>Two</a></li></ul></header></body>"
      iex> doc
      ...> |> xpath(
      ...>      ~x"//header",
      ...>      ul: [
      ...>        ~x"./ul",
      ...>        a: ~x"./li/a/text()"
      ...>      ]
      ...>    )
      %{ul: %{a: 'Two'}}
  """
  def xpath(parent, spec) when not is_tuple(parent) do
    parent |> parse |> xpath(spec)
  end

  def xpath(parent, %SweetXpath{is_list: true, is_value: true, cast_to: cast} = spec) do
    get_current_entities(parent, spec) |> Enum.map(&(_value(&1)) |> to_cast(cast))
  end

  def xpath(parent, %SweetXpath{is_list: true, is_value: false} = spec) do
    get_current_entities(parent, spec)
  end

  def xpath(parent, %SweetXpath{is_list: false, is_value: true, cast_to: cast} = spec) do
    get_current_entities(parent, spec) |> _value |> to_cast(cast)
  end

  def xpath(parent, %SweetXpath{is_list: false, is_value: false} = spec) do
    get_current_entities(parent, spec)
  end


  def xpath(parent, sweet_xpath, subspec) do
    if sweet_xpath.is_list do
      current_entities = xpath(parent, sweet_xpath)
      Enum.map(current_entities, fn (entity) -> xmap(entity, subspec, sweet_xpath) end)
    else
      current_entity = xpath(parent, sweet_xpath)
      xmap(current_entity, subspec, sweet_xpath)
    end
  end

  @doc ~S"""
  `xmap` returns a mapping with each value being the result of `xpath`

  Just as `xpath`, you can nest the mapping structure. Please see `xpath` for
  more detail.

  ## Examples

  Simple

      iex> import SweetXml
      iex> doc = "<h1><a>Some linked title</a></h1>"
      iex> doc |> xmap(a: ~x"//a/text()")
      %{a: 'Some linked title'}

  With optional mapping

      iex> import SweetXml
      iex> doc = "<body><header><p>Message</p><ul><li>One</li><li><a>Two</a></li></ul></header></body>"
      iex> doc |> xmap(message: ~x"//p/text()", a_in_li: ~x".//li/a/text()"l)
      %{a_in_li: ['Two'], message: 'Message'}

  With optional mapping and nesting

      iex> import SweetXml
      iex> doc = "<body><header><p>Message</p><ul><li>One</li><li><a>Two</a></li></ul></header></body>"
      iex> doc
      ...> |> xmap(
      ...>      message: ~x"//p/text()",
      ...>      ul: [
      ...>        ~x"//ul",
      ...>        a: ~x"./li/a/text()"
      ...>      ]
      ...>    )
      %{message: 'Message', ul: %{a: 'Two'}}
      iex> doc
      ...> |> xmap(
      ...>      message: ~x"//p/text()",
      ...>      ul: [
      ...>        ~x"//ul"k,
      ...>        a: ~x"./li/a/text()"
      ...>      ]
      ...>    )
      %{message: 'Message', ul: [a: 'Two']}
      iex> doc
      ...> |> xmap([
      ...>      message: ~x"//p/text()",
      ...>      ul: [
      ...>        ~x"//ul",
      ...>        a: ~x"./li/a/text()"
      ...>      ]
      ...>    ], true)
      [message: 'Message', ul: %{a: 'Two'}]
  """
  def xmap(parent, mapping), do: xmap(parent, mapping, %{is_keyword: false})

  def xmap(nil, _, %{is_optional: true}), do: nil

  def xmap(parent, [], atom) when is_atom(atom), do: xmap(parent, [], %{is_keyword: atom})

  def xmap(_, [], %{is_keyword: false}), do: %{}

  def xmap(_, [], %{is_keyword: true}), do: []

  def xmap(parent, [{label, spec} | tail], is_keyword) when is_list(spec) do
    [sweet_xpath | subspec] = spec
    result = xmap(parent, tail, is_keyword)
    Dict.put result, label, xpath(parent, sweet_xpath, subspec)
  end

  def xmap(parent, [{label, sweet_xpath} | tail], is_keyword) do
    result = xmap(parent, tail, is_keyword)
    Dict.put result, label, xpath(parent, sweet_xpath)
  end

  defp _value(entity) do
    cond do
      is_record? entity, :xmlText ->
        xmlText(entity, :value)
      is_record? entity, :xmlComment ->
        xmlComment(entity, :value)
      is_record? entity, :xmlPI ->
        xmlPI(entity, :value)
      is_record? entity, :xmlAttribute ->
        xmlAttribute(entity, :value)
      is_record? entity, :xmlObj ->
        xmlObj(entity, :value)
      true ->
        entity
    end
  end

  defp is_record?(data, kind) do
    is_tuple(data) and tuple_size(data) > 0 and :erlang.element(1, data) == kind
  end

  defp continuation_opts(enum, waiter \\ nil) do
    [{
       :continuation_fun,
       fn xcont, xexc, xstate ->
         case :xmerl_scan.cont_state(xstate).({:cont, []}) do
           {:suspended, bin, cont}->
             case waiter do
               nil -> :ok
               {parent, ref} ->
                 send(parent, {:wait, ref}) # continuation behaviour, pause and wait stream decision
                 receive do
                   {:continue, ^ref} -> # stream continuation fun has been called: parse to find more elements
                     :ok
                   {:halt, ^ref} -> # stream halted: halt the underlying stream and exit parsing process
                     cont.({:halt, []})
                     exit(:normal)
                 end
             end
             xcont.(bin, :xmerl_scan.cont_state(cont, xstate))
           {:done, _} -> xexc.(xstate)
         end
       end,
       &Enumerable.reduce(split_by_whitespace(enum), &1, fn bin, _ -> {:suspend, bin} end)
     },
     {
       :close_fun,
       fn xstate -> # make sure the XML end halts the binary stream (if more bytes are available after XML)
         :xmerl_scan.cont_state(xstate).({:halt,[]})
         xstate
       end
     }]
  end

  defp split_by_whitespace(enum) do
    reducer = fn
      :last, prev ->
        {[:erlang.binary_to_list(prev)], :done}
      bin, prev ->
        bin = if (prev === ""), do: bin, else: IO.iodata_to_binary([prev, bin])
        case split_last_whitespace(bin) do
          :white_bin -> {[], bin}
          {head, tail} -> {[:erlang.binary_to_list(head)], tail}
        end
    end

    Stream.concat(enum, [:last]) |> Stream.transform("", reducer)
  end

  defp split_last_whitespace(bin), do: split_last_whitespace(byte_size(bin) - 1, bin)
  defp split_last_whitespace(0, _), do: :white_bin
  defp split_last_whitespace(size, bin) do
    case bin do
      <<_::binary - size(size), h>> <> tail when h == ?\s or h == ?\n or h == ?\r or h == ?\t ->
        {head, _} = :erlang.split_binary(bin, size + 1)
        {head, tail}
      _ ->
        split_last_whitespace(size - 1, bin)
    end
  end

  defp flush_halt(pid, ref) do
    receive do
      {:event, ^ref, _} ->
        flush_halt(pid, ref) # flush all emitted elems after :halt
      {:wait, ^ref} ->
        send(pid, {:halt, ref}) # tell the continuation function to halt the underlying stream
    end
  end

  defp get_current_entities(parent, %SweetXpath{path: path, is_list: true}) do
    :xmerl_xpath.string(path, parent)
  end

  defp get_current_entities(parent, %SweetXpath{path: path, is_list: false}) do
    ret = :xmerl_xpath.string(path, parent)
    if is_record?(ret, :xmlObj) do
      ret
    else
      List.first(ret)
    end
  end

  defp to_cast(value, false), do: value
  defp to_cast(value, :string), do: to_string(value)
  defp to_cast(value, :integer), do: String.to_integer(to_string(value))

end
