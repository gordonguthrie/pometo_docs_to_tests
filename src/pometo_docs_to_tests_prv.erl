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
    io:format("making tests for ~p~n", [Root]),
    GeneratedTestDir = filename:join([Root, "test", "generated_tests"]),
    io:format("test dir is ~p~n", [GeneratedTestDir]),
    ok = del_dir(GeneratedTestDir),
    ok = file:make_dir(GeneratedTestDir),
    DocsFiles = get_files(filename:join([Root, "docs", "*"])),
    io:format("DocsFiles is ~p~n", [DocsFiles]),
    [generate_tests(X, GeneratedTestDir) || {X} <- DocsFiles],
    ok.

get_files(Root) ->
    RawFiles = filelib:wildcard(Root),
    io:format("RawFiles is ~p in ~p~n", [RawFiles, Root]),
    Files     = [{X}                   || X <- RawFiles, filename:extension(X) == ".md"],
    io:format("Files is ~p~n", [Files]),
    Dirs      = [filename:join(X, "*") || X <- RawFiles, filelib:is_dir(X)],
    io:format("Dirs is ~p~n", [Dirs]),
    DeepFiles = [get_files(X)          || X <- Dirs],
    io:format("DeepFiles is ~p~n", [DeepFiles]),
    [Files ++ lists:flatten(DeepFiles)].

generate_tests([], _GeneratedTestDir) -> ok;
generate_tests(File, GeneratedTestDir) ->
    {ok, Lines} = read_lines(File),
    Hash = binary:bin_to_list(base16:encode(crypto:hash(sha, Lines))),
    Basename = filename:basename(File, ".md"),
    FileName = Basename ++ "_" ++ Hash ++ "_tests",
    gen_test2(FileName, Lines, GeneratedTestDir),
    ok.

gen_test2(Filename, Lines, GeneratedTestDir) ->
    Body = gen_test3(Lines, ?IN_TEXT, #test{}, []),
    case Body of
        [] -> io:format("no tests for ~p~n", [Filename]),
              ok;
        _  -> io:format("outputing test for ~p~n", [Filename]),
              Disclaimer = "%%% DO NOT EDIT this test suite is generated by the pometo_docs_to_test rebar3 plugin\n\n",
              Header     = "-module(" ++ Filename ++ ").\n\n",
              Include    = "-include_lib(\"eunit/include/eunit.hrl\").\n\n",
              Export     = "-compile([export_all]).\n\n",
              Runner     = make_runner(),
              Module = Disclaimer ++ Header ++ Include ++ Export ++ Runner ++ Body,
              DirAndFile = string:join([GeneratedTestDir, Filename ++ ".erl"], "/"),
              ok = file:write_file(DirAndFile, Module)

    end,
    ok.

gen_test3([], _, _, Acc) -> lists:flatten(lists:reverse(Acc));
gen_test3(["```" ++ _Rest | T], ?GETTING_TEST, Test, Acc) ->
    gen_test3(T, ?IN_TEXT, Test, Acc);
gen_test3(["```" ++ _Rest | T], ?GETTING_RESULT, Test, Acc) ->
    #test{seq        = N,
          title      = Tt,
          codeacc    = C,
          resultsacc = R} = Test,
    NewTest = make_test(Tt, integer_to_list(N), lists:reverse(C), lists:reverse(R)),
    gen_test3(T, ?IN_TEXT, #test{seq = N + 1}, [NewTest| Acc]);
gen_test3([Line | T], ?GETTING_RESULT, Test, Acc) ->
    #test{resultsacc = R} = Test,
    gen_test3(T, ?GETTING_RESULT, Test#test{resultsacc = [Line | R]}, Acc);
gen_test3([Line | T], ?GETTING_TEST, Test, Acc) ->
    #test{codeacc = C} = Test,
    gen_test3(T, ?GETTING_TEST, Test#test{codeacc = [Line | C]}, Acc);
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

make_test(Title, Seq, Code, Results) ->
Title ++ "_" ++ Seq ++ "_test_() ->\n" ++
    "Code = \"" ++ string:join(Code, "\n") ++ "\",\n" ++
    "Expected = \"" ++ string:join(Results, "\n") ++ "\",\n" ++
    "run(Code, Expected).".

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

make_runner() ->
"%\n" ++
"% Test Runner\n" ++
"%\n" ++
"\n"
"run(Code, Expected) when is_list(Code) andalso is_list(Expected) ->\n" ++
"   Tokens    = pometo_lexer:get_tokens(Code),\n" ++
"   {ok, AST} = pometo_parser:parse(Tokens),\n" ++
"   Got = :pometo_runtime.run_ast(AST, [])\n," ++
"   ?_assert(Got, Expected).\n" ++
"\n" ++
"%\n" ++
"% Tests\n" ++
"%\n" ++
"\n".


