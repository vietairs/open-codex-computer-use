# Configuration

The screenshot config file defaults to `~/.config/ocu/config.json` (or `$XDG_CONFIG_HOME/ocu/config.json`). You can edit it directly; if it does not exist, the defaults below apply:

```json
{
  "image": {
    "format": "png",
    "jpegQuality": 0.8,
    "maxLongEdgePixels": 1280,
    "scaleDownAfterMaxSize": true,
    "discardBelowPixelCount": 64,
    "captureTimeout": 5
  }
}
```

These settings currently apply to macOS screenshots only. Changes take effect on the next capture. Environment variables are also supported, with precedence: environment > config file > defaults.

The file holds screenshot encoding preferences and nothing else. It cannot enable lock-screen control, change a permission, or relax any guard, and nothing in it is executed. Every value is validated; a bad value is ignored with a warning on stderr and the next layer (file, then default) applies. A file that is not a regular file, is larger than 64 KiB, or is not valid JSON is ignored the same way. The file is opened once without blocking and every check runs on that open descriptor, so a path swapped for a fifo or a growing file after the open can neither block the reader nor exceed the size limit.

## Configure from the command line

You can also use `ocu config`. Changes are saved to the file above (mode `0600`, written atomically, unknown fields preserved):

```bash
# View settings and where each value comes from
ocu config

# Switch to JPG
ocu config set image.format jpg

# Read one setting
ocu config get image.format

# Restore the default (environment overrides still take priority)
ocu config reset image.format

# Show the config file path
ocu config path
```

You can use `open-computer-use` in place of `ocu`. `ocu config` only reads and writes the JSON file; it never starts the native runtime. If the config file is a symlink (for example into a dotfiles repository), `ocu config set` and `reset` write through to its target and the link stays in place.

## Settings

| Setting | Environment variable | Default | Description | Example command |
| --- | --- | --- | --- | --- |
| `image.format` | `OPEN_COMPUTER_USE_IMAGE_FORMAT` | `png` | Output format: `png` or `jpg` (`jpeg` is accepted as an alias). | `ocu config set image.format jpg` |
| `image.jpegQuality` | `OPEN_COMPUTER_USE_IMAGE_JPEG_QUALITY` | `0.8` | JPG quality, from `0` to `1`. Only affects JPG. | `ocu config set image.jpegQuality 0.9` |
| `image.maxLongEdgePixels` | `OPEN_COMPUTER_USE_IMAGE_MAX_DIMENSION` | `1280` | Maximum long edge in pixels. Integer `1-16384`; `null` disables the limit. | `ocu config set image.maxLongEdgePixels 1920` |
| `image.scaleDownAfterMaxSize` | `OPEN_COMPUTER_USE_IMAGE_SCALE_DOWN_AFTER_MAX_SIZE` | `true` | If the long edge exceeds the limit, `true` resizes proportionally and `false` omits the screenshot. | `ocu config set image.scaleDownAfterMaxSize false` |
| `image.discardBelowPixelCount` | `OPEN_COMPUTER_USE_IMAGE_DISCARD_BELOW_PIXEL_COUNT` | `64` | Omit when width x height is below this value; equality is retained. Integer `0-268435456`; `0` disables filtering. For example, `4096` is the area of `64x64`. Resized images are checked too. | `ocu config set image.discardBelowPixelCount 4096` |
| `image.captureTimeout` | `OPEN_COMPUTER_USE_IMAGE_CAPTURE_TIMEOUT` | `5` | ScreenCaptureKit capture timeout, in seconds. Range `0.01-30`, so a stalled capture holds its call for at most 30 seconds. | `ocu config set image.captureTimeout 10` |

`OPEN_COMPUTER_USE_CONFIG_FILE` points at a different config file (absolute path only).

## Behavior notes

- The result image is capped at about 900 KB: when an encoded screenshot is larger, it is re-encoded at smaller scales until it fits or reaches a quarter of the captured size. This byte cap is not configurable and applies to both formats. Coordinate tools always map x/y against the pixel size of the image actually returned.
- When a screenshot is omitted (below the pixel threshold, or over the long-edge limit with `scaleDownAfterMaxSize` off), `get_app_state` still returns the accessibility tree plus a note with the reason, and coordinate `click` / `drag` are refused while the newest snapshot of that app carries the omission note. The note appears in results that would have carried the screenshot: the full state, or an action result that asked for one or found an empty window. A later refresh that takes no screenshot (an element-index action on a window with content, for example) clears the note; x/y input is then mapped against the last screenshot returned for the unchanged window, and fails closed when the window changed. Element-index actions keep working throughout.
- WebP output is not offered. It needs a third-party encoder (libwebp) that this fork does not take as a dependency.
- With the macOS app agent, the proxy in the calling host's own process resolves the settings (environment over config file over defaults), validates them, and sends only the validated `OPEN_COMPUTER_USE_IMAGE_*` values with calls that can take a screenshot. The agent applies them to that call alone: it never opens a config file or a config path named by a caller (the proxy also reads a `call --args-file` or `--calls-file` path itself, relative to the caller's working directory, and sends the JSON inline), ignores `OPEN_COMPUTER_USE_CONFIG_FILE` and any value in its own launch environment, and does not write the settings to its process environment. Hosts that share one agent therefore neither leak settings into each other's calls nor wait on each other because of them. `decide_next_action` and `list_apps` read no screenshot settings.
