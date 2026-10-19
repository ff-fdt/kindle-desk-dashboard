import pytest
from math_text import split_math, prepare_state, MAX_FORMULAS
from conversations import plain


@pytest.mark.parametrize('source, expected, display', [
    (r'能量 $E=mc^2$。', 'E=mc^2', False),
    (r'频率 \(\omega_{q}\) 已收敛。', r'\omega_{q}', False),
    (r'$$\frac{a}{b}$$', r'\frac{a}{b}', True),
    ('\\[\n\\begin{pmatrix}1&2\\\\3&4\\end{pmatrix}\n\\]', r'\begin{pmatrix}1&2\\3&4\end{pmatrix}', True),
])
def test_standard_delimiters_preserve_math(source, expected, display):
    math = [r for r in split_math(source) if r['kind']=='math']
    assert len(math)==1 and math[0]['text']==expected and math[0]['display']==display
    assert ''.join(r.get('source',r['text']) for r in split_math(source))==source


@pytest.mark.parametrize('source', [r'价格 $10 和 $20。', r'显示 \$x\$。', r'尚未输入完 \frac{a}', r'等待 \[x+1', '$ with spaces $'])
def test_prose_currency_escaping_and_incomplete_math_stay_literal(source):
    assert all(r['kind']=='text' for r in split_math(source))
    assert ''.join(r['text'] for r in split_math(source))==source


def test_markdown_cleanup_does_not_rewrite_math():
    source = r'**结果 $A^{**} B^{**}$ 已完成**，`plain`。'
    assert plain(source)==r'结果 $A^{**} B^{**}$ 已完成，plain。'
    assert plain('保留 <oai-mem-citation>隐藏 $x$</oai-mem-citation> 内容')=='保留  内容'


def test_formula_count_is_bounded_without_losing_tail():
    source=' '.join(f'$x_{i}$' for i in range(100))
    runs=split_math(source)
    assert sum(r['kind']=='math' for r in runs)==MAX_FORMULAS
    assert ''.join(r.get('source',r['text']) for r in runs)==source


def test_prepare_state_preserves_conversation_and_does_not_mutate_input():
    item={'question':r'$x^2$', 'reply':r'\[x=2\]','status':'completed'}
    state={'codex':{'items':[item]}}
    out=prepare_state(state)
    assert out['codex']['items'][0]['question_runs'][0]['text']=='x^2'
    assert out['codex']['items'][0]['reply_runs'][0]['display']
    assert 'question_runs' not in item
