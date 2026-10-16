from desk import next_minute, refresh_event


def test_refresh_stays_aligned_after_manual_refresh():
    assert next_minute(120.0) == 180
    assert next_minute(135.5) == 180
    assert next_minute(179.99) == 180
    assert next_minute(180) == 240


def test_only_refresh_button_requests_refresh():
    assert refresh_event({'seq':'a','x':1050,'y':1540})
    for event in [None, {}, {'seq':'a','x':200,'y':500},
                  {'seq':'a','x':1050,'y':1576}, {'seq':'a','x':'1050','y':1540}]:
        assert not refresh_event(event)
