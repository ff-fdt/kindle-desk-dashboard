import json
from conversations import RolloutReader, question_text


def record(kind, **fields):
    return json.dumps({'timestamp':'2026-10-16T10:00:00Z','type':'event_msg',
                       'payload':{'type':kind,**fields}}, ensure_ascii=False)+'\n'


def message(role, text, turn):
    return record('item_completed', turn_id=turn, item={'type':role,
                  'content':[{'type':'text','text':text}]})


def test_question_and_reply_are_matched_by_turn_id(tmp_path):
    p=tmp_path/'log';p.write_text(record('task_started',turn_id='a')+message('UserMessage','问题甲','a')+
        record('task_complete',turn_id='a',last_agent_message='回复甲')+
        record('task_started',turn_id='b')+message('UserMessage','问题乙','b')+
        message('AgentMessage','乙的进展','b'))
    items=RolloutReader(p).read()['items']
    assert [(t['question'],t['reply'],t['status']) for t in items]==[
        ('问题甲','回复甲','completed'),('问题乙','乙的进展','running')]


def test_partial_record_is_consumed_after_writer_finishes(tmp_path):
    p=tmp_path/'log';data=message('UserMessage','完整问题','a');p.write_text(data[:-7])
    reader=RolloutReader(p);assert reader.read()['items']==[]
    with p.open('a') as f:f.write(data[-7:])
    assert reader.read()['items'][0]['question']=='完整问题'
    assert len(reader.read()['items'])==1


def test_prompt_wrappers_do_not_appear_on_panel():
    assert question_text('# Files mentioned\n/private/file\n## My request:\n改好页面\n<image name="1">')=='改好页面'
    assert question_text('<environment_context>secret</environment_context>')==''
    assert question_text('<send_user_message_question_reply>[{"answer":"可以"}]</send_user_message_question_reply>')=='可以'


def test_aborted_turn_not_mislabeled_completed_and_steering_preserved(tmp_path):
    p=tmp_path/'log';p.write_text(record('task_started',turn_id='a')+message('UserMessage','原问题','a')+
        message('UserMessage','补充要求','a')+message('AgentMessage','处理中','a'))
    reader=RolloutReader(p);assert reader.read()['items'][0]['question']=='原问题\n\n补充要求'
    with p.open('a') as f:f.write(record('task_aborted',turn_id='a'))
    assert reader.read()['items']==[]


def test_large_tool_record_uses_bounded_memory_and_preserves_next_turn(tmp_path):
    import tracemalloc
    p = tmp_path/'large.jsonl'
    with p.open('wb') as f:
        f.write(b'{"type":"response_item","payload":{"image":"')
        for _ in range(256):
            f.write(b'a' * 65536)
        f.write(b'"}}\n')
        f.write(message('UserMessage', '最新问题', 'latest').encode())
    tracemalloc.start()
    result = RolloutReader(p).read()
    _, peak = tracemalloc.get_traced_memory()
    tracemalloc.stop()
    assert result['items'][0]['question'] == '最新问题'
    assert peak < 1024 * 1024


def test_large_partial_record_resumes_at_its_boundary(tmp_path):
    p = tmp_path/'partial.jsonl'
    p.write_bytes(b'{"type":"response_item","payload":"' + b'a' * 100000)
    reader = RolloutReader(p)
    assert not reader.read()['items']
    assert reader.offset == 0
    with p.open('ab') as f:
        f.write(b'"}\n' + message('UserMessage', 'next', 'b').encode())
    assert reader.read()['items'][0]['question'] == 'next'
    assert reader.offset == p.stat().st_size


def test_turns_and_steering_text_stay_bounded(tmp_path):
    from conversations import MAX_TEXT, MAX_TURNS
    p = tmp_path/'turns.jsonl'
    with p.open('w') as f:
        for n in range(50):
            f.write(message('UserMessage', str(n) + 'x' * MAX_TEXT, str(n)))
            f.write(message('UserMessage', 'steering' * MAX_TEXT, str(n)))
    reader = RolloutReader(p)
    result = reader.read()
    assert len(reader.turns) == MAX_TURNS
    assert result['items'][-1]['turn_id'] == '49'
    assert all(len(t['question']) <= MAX_TEXT for t in reader.turns.values())
    assert all(sum(map(len, t['questions'])) <= MAX_TEXT for t in reader.turns.values())


def test_collector_evicts_archived_conversations(tmp_path):
    import sqlite3
    from conversations import CodexCollector
    db = tmp_path/'state.sqlite'
    log = tmp_path/'log'
    log.write_text(message('UserMessage', 'visible', 'a'))
    with sqlite3.connect(db) as c:
        c.execute('CREATE TABLE threads (id, title, rollout_path, source, archived, updated_at)')
        c.execute('INSERT INTO threads VALUES (?, ?, ?, ?, ?, ?)', ('a', 'demo', str(log), 'cli', 0, 1))
    collector = CodexCollector(db)
    assert collector.snapshot()['items']
    assert len(collector.cache) == 1
    with sqlite3.connect(db) as c:
        c.execute('UPDATE threads SET archived=1')
    assert collector.snapshot()['items'] == []
    assert collector.cache == {}


def test_heartbeat_is_hidden_without_hiding_user_question(tmp_path):
    p = tmp_path/'log'
    p.write_text(message('UserMessage', '查看 heartbeat 日志', 'human') +
                 record('task_complete', turn_id='human', last_agent_message='已查看') +
                 message('UserMessage', '<heartbeat>\n<instructions>poll</instructions>\n</heartbeat>', 'timer') +
                 record('task_complete', turn_id='timer', last_agent_message=''))
    items = RolloutReader(p).read()['items']
    assert [x['turn_id'] for x in items] == ['human']
    assert question_text(' <heartbeat>## My request: hidden</heartbeat>') == ''
