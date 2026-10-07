class_name PlayerNameText
extends Translation

# 文案里的 {name} 在显示时换成玩家给主角取的名字。
# 替换做在翻译这一层：把已载入的每份译文包一层，游戏里任何地方用 tr() 取到的文字都已经换好了，
# 对话框、选项、提示等界面代码都不用知道占位符的存在。还没取名时用默认名（PLAYER_DEFAULT_NAME）。
# 文案表（localization/game.csv）里写 {name}，中英文都要写；不要把具体名字写进文案。

const PLACEHOLDER := "{name}"

static var player_name := ""

var inner: Translation


# 把当前已载入的译文都包上一层；重复调用没有副作用。启动时调用一次，运行中重建译文后再调用一次。
static func install() -> void:
	for code: String in TranslationServer.get_loaded_locales():
		var translation := TranslationServer.get_translation_object(code)
		if translation == null or translation is PlayerNameText:
			continue
		TranslationServer.remove_translation(translation)
		TranslationServer.add_translation(around(translation))


static func around(translation: Translation) -> PlayerNameText:
	var wrapped := PlayerNameText.new()
	wrapped.inner = translation
	wrapped.locale = translation.locale
	return wrapped


func _get_message(src_message: StringName, context: StringName) -> StringName:
	if inner == null:
		return &""
	var text := String(inner.get_message(src_message, context))
	if PLACEHOLDER in text:
		var shown := player_name if not player_name.is_empty() else String(inner.get_message(&"PLAYER_DEFAULT_NAME"))
		text = text.replace(PLACEHOLDER, shown)
	return StringName(text)


func _get_plural_message(src_message: StringName, src_plural_message: StringName, n: int, context: StringName) -> StringName:
	return inner.get_plural_message(src_message, src_plural_message, n, context) if inner != null else &""
