import importlib.util
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).parents[1] / "scripts" / "render_answers.py"
SPEC = importlib.util.spec_from_file_location("render_answers", SCRIPT)
assert SPEC is not None
assert SPEC.loader is not None
render_answers = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(render_answers)


class RenderAnswersTest(unittest.TestCase):
    def test_renders_supported_markdown(self) -> None:
        source = "# Answers\n\n**Question:** What?\n\n- First\n- `code`\n\n```text\n<unsafe>\n```"
        rendered = render_answers.render_markdown(source)
        self.assertIn("<h1>Answers</h1>", rendered)
        self.assertIn("<strong>Question:</strong> What?", rendered)
        self.assertIn("<ul><li>First</li><li><code>code</code></li></ul>", rendered)
        self.assertIn("&lt;unsafe&gt;", rendered)
        self.assertNotIn("<unsafe>", rendered)

    def test_each_question_heading_opens_one_card(self) -> None:
        source = "### Q1 — First\n\n**Answer:** one\n\n---\n\n### Q2 — Second\n\n**Answer:** two"
        rendered = render_answers.render_markdown(source)
        self.assertEqual(2, rendered.count('<div class="qa-card">'))
        self.assertEqual(2, rendered.count("</div>\n</div>"))
        self.assertNotIn("---", rendered)
        self.assertIn('<span class="qa-number">Q1</span>', rendered)
        self.assertIn('<div class="qa-body">', rendered)

    def test_rule_and_level_two_heading_close_the_open_card(self) -> None:
        source = "### Q1 — First\n\nBody\n\n## Open Decisions\n\n### O1 — Pending\n\nText"
        rendered = render_answers.render_markdown(source)
        self.assertLess(rendered.index("</div>\n</div>"), rendered.index("<h2>Open Decisions</h2>"))
        self.assertEqual(2, rendered.count('<div class="qa-card">'))

    def test_blockquote_renders_as_quote(self) -> None:
        rendered = render_answers.render_markdown("> Session: Planner")
        self.assertEqual("<blockquote>Session: Planner</blockquote>", rendered)

    def test_rendering_is_deterministic(self) -> None:
        source = "# Answers\n\nSame input."
        self.assertEqual(render_answers.render_document(source), render_answers.render_document(source))

    def test_cli_writes_html_next_to_markdown(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "answers.md"
            source.write_text("# Answers\n\n### Q1 — Yes\n\n**Answer:** yes", encoding="utf-8")
            previous_argv = sys.argv
            try:
                sys.argv = [str(SCRIPT), str(source)]
                render_answers.main()
            finally:
                sys.argv = previous_argv
            output = source.with_name("answers.html")
            self.assertTrue(output.is_file())
            self.assertIn("<strong>Answer:</strong> yes", output.read_text(encoding="utf-8"))


if __name__ == "__main__":
    unittest.main()
