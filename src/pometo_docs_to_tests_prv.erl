-module(pometo_docs_to_tests_prv).

-export([init/1, do/1, format_error/1]).

-define(PROVIDER, pometo_docs_to_tests).
-define(DEPS, [app_discovery]).

-define(IN_TEXT,        1).
-define(GETTING_TEST,   2).
-define(GETTING_RESULT, 3).

-define(SPACE, 32).
-define(UNDERSCORE, 95).

-record(test, {
               seq        = 1,
               title      = "",
               codeacc    = [],
               resultsacc = []
    }).

%% ===================================================================
%% Public API
%% ===================================================================
-spec init(rebar_state:t()) -> {ok, rebar_state:t()}.
init(State) ->
    Provider = providers:create([
            {name, ?PROVIDER},                        % The 'user friendly' name of the task
            {module, ?MODULE},                        % The module implementation of the task
            {bare, true},                             % The task can be run by the user, always true
            {deps, ?DEPS},                            % The list of dependencies
            {example, "rebar3 pometo_docs_to_tests"}, % How to use the plugin
            {opts, []},                               % list of options understood by the plugin
            {short_desc, "builds eunit tests from pometo markdown documentation"},
            {desc, "builds eunit tests from pometo markdown documentation"}
    ]),
    {ok, rebar_state:add_provider(State, Provider)}.


-spec do(rebar_state:t()) -> {ok, rebar_state:t()} | {error, string()}.
do(State) ->
    lists:foreach(fun make_tests/1, rebar_state:project_apps(State)),
    {ok, State}.

-spec format_error(any()) ->  iolist().
format_error(Reason) ->
    io_lib:format("~p", [Reason]).

make_tests(App) ->
    Root = rebar_app_info:dir(App),
    GeneratedTestDir = filename:join([Root, "test", "generated_tests"]),
    case filelib:is_dir(GeneratedTestDir) of
      true  -> io:format("* deleting the generated test directory ~p~n", [GeneratedTestDir]),
               ok = del_dir(GeneratedTestDir);
      false -> ok
    end,
    ok = file:make_dir(GeneratedTestDir),
    DocsFiles = lists:flatten(get_files(filename:join([Root, "docs", "*"]))),
    [generate_tests(X, GeneratedTestDir) || {X} <- DocsFiles],
    ok.

get_files(Root) ->
    RawFiles = filelib:wildcard(Root),
    Files     = [{X}                   || X <- RawFiles, filename:extension(X) == ".md"],
    Dirs      = [filename:join(X, "*") || X <- RawFiles, filelib:is_dir(X)],
    DeepFiles = [get_files(X)          || X <- Dirs],
    [Files ++ lists:flatten(DeepFiles)].

generate_tests([], _GeneratedTestDir) -> ok;
generate_tests(File, GeneratedTestDir) ->
    {ok, Lines} = read_lines(File),
    Basename = filename:basename(File, ".md"),
    FileName = Basename ++ "_tests",
    gen_test2(FileName, Lines, GeneratedTestDir),
    ok.

gen_test2(Filename, Lines, GeneratedTestDir) ->
    Body = gen_test3(Lines, ?IN_TEXT, #test{}, []),
    case Body of
        [] -> ok;
        _  -> io:format("* writing test ~p~n", [Filename ++ ".erl"]),
              Disclaimer = "%%% DO NOT EDIT this test suite is generated by the pometo_docs_to_test rebar3 plugin\n\n",
              Comments   = "%%% The documentation is usually written Simple -> Complicated\n" ++
                           "%%% This test suite shows the tests in the reverse of that order.\n"  ++
                           "%%% The first failing test you should fix is the bottom one - the simplest one\n\n",
              Header     = "-module(" ++ Filename ++ ").\n\n",
              Include    = "-include_lib(\"eunit/include/eunit.hrl\").\n\n",
              Export     = "-compile([export_all]).\n\n",
              Module = Disclaimer ++ Comments ++ Header ++ Include ++ Export ++ Body,
              DirAndFile = string:join([GeneratedTestDir, Filename ++ ".erl"], "/"),
              ok = file:write_file(DirAndFile, Module)
    end,
    ok.

%% Generally docs pages are written from Simple -> Complicated
%% However when you run rebar3 eunit it is easier to have the tests Complicated -> Simple
%% as then the first failing test you should fix appears at the bottom
gen_test3([], _, _, Acc) -> lists:flatten(Acc);
gen_test3(["```" ++ _Rest | T], ?GETTING_TEST, Test, Acc) ->
    gen_test3(T, ?IN_TEXT, Test, Acc);
gen_test3(["```" ++ _Rest | T], ?GETTING_RESULT, Test, Acc) ->
    #test{seq        = N,
          title      = Tt,
          codeacc    = C,
          resultsacc = R} = Test,
    NewTest1 = make_test(Tt, "interpreter", integer_to_list(N), lists:reverse(C), lists:reverse(R)),
    NewTest2 = make_test(Tt, "compiler",    integer_to_list(N), lists:reverse(C), lists:reverse(R)),
    NewTest2 = make_test(Tt, "compiler_lazy",    integer_to_list(N), lists:reverse(C), lists:reverse(R)),
    %%% we preserve the title, the sequence number will keep the test name different
    %%% if there isn't another title given anyhoo
    gen_test3(T, ?IN_TEXT, #test{seq = N + 1, title = Tt}, [NewTest2, NewTest1 | Acc]);
gen_test3([Line | T], ?GETTING_RESULT, Test, Acc) ->
    #test{resultsacc = R} = Test,
    gen_test3(T, ?GETTING_RESULT, Test#test{resultsacc = [string:trim(Line, trailing, "\n") | R]}, Acc);
gen_test3([Line | T], ?GETTING_TEST, Test, Acc) ->
    #test{codeacc = C} = Test,
    gen_test3(T, ?GETTING_TEST, Test#test{codeacc = [string:trim(Line, trailing, "\n") | C]}, Acc);
gen_test3(["```pometo_results" ++ _Rest | T], ?IN_TEXT, Test, Acc) ->
    gen_test3(T, ?GETTING_RESULT, Test, Acc);
gen_test3(["```pometo" ++ _Rest | T], ?IN_TEXT, Test, Acc) ->
    gen_test3(T, ?GETTING_TEST, Test, Acc);
gen_test3(["## " ++ Title | T], ?IN_TEXT, Test, Acc) ->
    NewTitle = normalise(Title),
    gen_test3(T, ?IN_TEXT, Test#test{title = NewTitle}, Acc);
gen_test3([_H | T], ?IN_TEXT, Test, Acc) ->
    gen_test3(T, ?IN_TEXT, Test, Acc).

normalise(Text) ->
    norm2(string:to_lower(Text), []).

norm2([], Acc) -> lists:reverse(Acc);
norm2([H | T], Acc) when H >= 97 andalso H =< 122 ->
    norm2(T, [H | Acc]);
norm2([?SPACE | T], Acc) ->
    norm2(T, [?UNDERSCORE | Acc]);
norm2([_H | T], Acc) ->
     norm2(T, Acc).

make_test(Title, Type, Seq, Code, Results) ->
  Title2 = case Title of
    [] -> "anonymous";
    _  -> Title
  end,
  NameRoot = Title2 ++ "_" ++ Seq ++ "_" ++ Type,
  Main = NameRoot ++ "_test_() ->\n" ++
    "    Code     = [\"" ++ string:join(Code,    "\",\n    \"") ++ "\"],\n" ++
    "    Expected = \"" ++ string:join(Results, "\\n\" ++ \n    \"") ++ "\",\n",
  Call = case Type of
    "interpreter" ->
      "    Got = pometo_test_helper:run_" ++ Type ++ "_test(Code),\n";
    "compiler" ->
      "    Got = pometo_test_helper:run_" ++ Type ++ "_test(\"" ++ NameRoot ++ "\", Code),\n";
    "compiler_lazy" ->
      "    Got = pometo_test_helper:run_" ++ Type ++ "_lazy_test(\"" ++ NameRoot ++ "\", Code),\n"
    end,
  Printing = "    % ?debugFmt(\" in " ++ NameRoot ++ "~nCode:~n~ts~nExp:~n~ts~nGot:~n~ts~n\", [Code, Expected, Got]),\n",
  Assert   = "    ?_assertEqual(Expected, Got).\n\n",
  Main ++ Call ++ Printing ++ Assert.

read_lines(File) ->
    case file:open(File, read) of
        {error, Err} -> {error, Err};
        {ok, Id}     -> read_l2(Id, [])
    end.

read_l2(Id, Acc) ->
    case file:read_line(Id) of
        {ok, Data}   -> read_l2(Id, [Data | Acc]);
        {error, Err} -> {error, Err};
        eof          -> {ok, lists:reverse(Acc)}
    end.

del_dir(Dir) ->
   lists:foreach(fun(D) ->
                    ok = file:del_dir(D)
                 end, del_all_files([Dir], [])).

del_all_files([], EmptyDirs) ->
   EmptyDirs;
del_all_files([Dir | T], EmptyDirs) ->
   {ok, FilesInDir} = file:list_dir(Dir),
   {Files, Dirs} = lists:foldl(fun(F, {Fs, Ds}) ->
                                  Path = filename:join([Dir, F]),
                                  case filelib:is_dir(Path) of
                                     true ->
                                          {Fs, [Path | Ds]};
                                     false ->
                                          {[Path | Fs], Ds}
                                  end
                               end, {[],[]}, FilesInDir),
   lists:foreach(fun(F) ->
                         ok = file:delete(F)
                 end, Files),
   del_all_files(T ++ Dirs, [Dir | EmptyDirs]).