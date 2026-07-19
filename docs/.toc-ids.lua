-- Assign heading IDs matching the document's manual TOC anchors:
--   heading text -> remove ASCII punctuation -> lowercase -> spaces to hyphens
-- e.g. "2.1 RAG 知识库 Subagent" -> "21-rag-知识库-subagent"
-- This keeps leading digits, which pandoc's auto_identifiers strips.
local stringify = pandoc.utils.stringify

function Header(el)
  local s = stringify(el.content)
  s = s:gsub("%p", "")                     -- ASCII punctuation (periods, etc.)
  s = s:gsub("\xE3\x80[\x80-\xBF]", "")    -- CJK punctuation block U+3000-U+303F (、。〈〉等)
  s = s:gsub("\xEF[\xBC-\xBF][\x80-\xBF]", "")  -- fullwidth forms U+FF00-U+FFFF (：（）等)
  s = s:lower()                            -- lowercase ASCII; CJK unaffected
  s = s:gsub("%s+", "-")                   -- collapse runs of whitespace to single hyphen
  s = s:gsub("^-", "")                     -- trim leading hyphen
  s = s:gsub("-$", "")                     -- trim trailing hyphen
  el.identifier = s
  return el
end
