 -module(couchc_test).
 -compile(export_all).
 -include_lib("eunit/include/eunit.hrl").

-include("couch_db.hrl").

do_test(Fun) ->
    Options = [{user_ctx, #user_ctx{roles=[<<"_admin">>]}}],
    {ok, Db} = couchc:create_db("couchc_testdb", Options),
    try
        Fun(Db)
    after
        ok = couchc:delete_db("couchc_testdb", Options)
    end.


createdb_test() ->
    {ok, Db} = couchc:create_db("couchc_testdb"),
    {ok, Info} = couchc:db_info(Db),
    ?assert(proplists:get_value(db_name, Info) == <<"couchc_testdb">>),
    {ok, Db1} = couchc:open_db("couchc_testdb"),
    {ok, Info1} = couchc:db_info(Db1),
    ?assert(proplists:get_value(db_name, Info1) == <<"couchc_testdb">>),
    ok = couchc:delete_db("couchc_testdb"),
    Result = couchc:open_db("couchc_testdb"),
    ?assert(Result == {error,{not_found,no_db_file}}).

handle_doc_test() ->
    do_test(fun(Db) ->
        {ok, DocId, DocRev} = couchc:save_doc(Db, 
            {[{<<"test">>, <<"blah">>}]}),
        ?assert(is_binary(DocId)),
        {ok, {DocProps}} = couchc:open_doc(Db, DocId),

        ?assertEqual(<<"blah">>,
            proplists:get_value(<<"test">>, DocProps)),

        ?assertEqual(DocRev,
            proplists:get_value(<<"_rev">>, DocProps)),

        Doc1 = {[{<<"test1">>, <<"blah1">>}|DocProps]},
        
        {ok, DocId1, DocRev1} = couchc:save_doc(Db, Doc1),
        ?assertEqual(DocId, DocId1),
        ?assert(DocRev =/= DocRev1),

        {ok, {DocProps1}} = couchc:open_doc(Db, DocId),
        ?assertEqual(<<"blah">>,
            proplists:get_value(<<"test">>, DocProps1)),
        ?assertEqual(<<"blah1">>,
            proplists:get_value(<<"test1">>, DocProps1)),
        
        {ok, DocId2, DocRev2} = couchc:delete_doc(Db, {DocId, DocRev1}),
        ?assertEqual(DocId1, DocId2),
        ?assert(DocRev1 =/= DocRev2),

        Result = couchc:open_doc(Db, DocId),
        ?assert(Result == {error, {not_found, deleted}}),
        Result1 = couchc:open_doc(Db, <<"unknown id">>),
        ?assert(Result1 == {error, {not_found, missing}})
    end).

bulkdocs_test() ->
    do_test(fun(Db) ->
        Docs = [
            {[{<<"_id">>, <<"a">>}, {<<"v">>, 1}]},
            {[{<<"_id">>, <<"b">>}, {<<"v">>, 1}]}],
        Results = couchc:save_docs(Db, Docs),
        ?assertEqual(2, length(Results)),
        [R|_] = Results,
        {RP} = R,
        ?assertEqual(true, proplists:get_value(ok, RP)),
        DocId = proplists:get_value(id, RP),
        {ok, {DocProps}} = couchc:open_doc(Db, DocId),
        ?assertEqual(1, proplists:get_value(<<"v">>, DocProps)),
        DocsToDelete = lists:map(fun({P}) ->
                    Id = proplists:get_value(id, P),
                    Rev = proplists:get_value(rev, P),
                    {[{<<"_id">>, Id},
                      {<<"_rev">>, Rev}]}
                    end, Results),
        Results1 = couchc:delete_docs(Db, DocsToDelete),
        ?assertEqual(2, length(Results1)),
        Result = couchc:open_doc(Db, DocId),
        ?assert(Result == {error, {not_found, deleted}})
    end).

alldocs_test() ->
    do_test(fun(Db) ->
        Docs = [
            {[{<<"_id">>, <<"a">>}, {<<"v">>, 1}]},
            {[{<<"_id">>, <<"b">>}, {<<"v">>, 2}]}],
        Results = couchc:save_docs(Db, Docs),
        ?assertEqual(2, length(Results)),
        R = couchc:all(Db),
        ?assertMatch({ok, {_, _, _}}, R),
        {ok, {TotalRowsCount, Offset, Results1}} = R,
        ?assertEqual(2, TotalRowsCount),
        ?assertEqual(2, Offset),
        [{DP}|_] = Results1,
        DocId = proplists:get_value(id, DP),

        ?assert(DocId =/= undefined),        
        ?assert(lists:member(DocId, [<<"a">>, <<"b">>])),

        {ok, Doc} = couchc:open_doc(Db, <<"a">>),
        {ok, _, _} = couchc:delete_doc(Db, Doc),
        {ok, {TotalRowsCount1, _, _}} = couchc:all(Db),
        ?assertEqual(1, TotalRowsCount1)
    end).


view_test() ->
    do_test(fun(Db) ->
        DesignDoc = {[
            {<<"_id">>, <<"_design/test">>},
            {<<"language">>,<<"javascript">>},
            {<<"views">>,
                {[{<<"v1">>,
                    {[{<<"map">>,
                        <<"function (doc) {\n if (doc.t == \"test\") {\n emit(doc._id, doc);\n}\n}">>
                    }]}
        }]}}]},
        Docs = [
            {[{<<"_id">>, <<"a">>}, {<<"v">>, 1}, {<<"t">>, <<"test">>}]},
            {[{<<"_id">>, <<"b">>}, {<<"v">>, 2}, {<<"t">>, <<"test">>}]}],
        {ok, _, _} = couchc:save_doc(Db, DesignDoc),
        Results = couchc:save_docs(Db, Docs),
        ?assertEqual(2, length(Results)),
        R = couchc:all(Db, {<<"test">>, <<"v1">>}),
        ?assertMatch({ok, {_, _, _}}, R),
        {ok, {TotalRowsCount, Offset, Results1}} = R,
        ?assertEqual(2, TotalRowsCount),
        ?assertEqual(2, Offset),
        [{DP}|_] = Results1,
        DocId = proplists:get_value(id, DP),

        ?assert(DocId =/= undefined),        
        ?assert(lists:member(DocId, [<<"a">>, <<"b">>])),

        {ok, Doc} = couchc:open_doc(Db, <<"a">>),
        {ok, _, _} = couchc:delete_doc(Db, Doc),
        {ok, {TotalRowsCount1, _, _}} = couchc:all(Db, {<<"test">>, <<"v1">>}),
        ?assertEqual(1, TotalRowsCount1)
    end).


