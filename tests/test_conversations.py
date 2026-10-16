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
