THEMES_DIR = themes

theme:
	@mkdir -p $(THEMES_DIR)
	@git clone --recursive git@github.com:jvanz/pelican-hyde.git $(THEMES_DIR)/hyde
