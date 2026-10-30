#!/bin/bash
# Xcode 把 DakaLing.xcodeproj 当成一个包。拷贝时如果包里的 project.pbxproj 掉了，就补回去再打开。
cd "$(dirname "$0")" || exit 1

if [ -e DakaLing.xcodeproj ] && [ ! -d DakaLing.xcodeproj ]; then
  echo "DakaLing.xcodeproj 现在是一个普通文件，先改回工程包。"
  backup="$(mktemp)"
  mv DakaLing.xcodeproj "$backup"
  mkdir -p DakaLing.xcodeproj
  if head -n 1 "$backup" | grep -q 'UTF8'; then
    mv "$backup" DakaLing.xcodeproj/project.pbxproj
  else
    rm -f "$backup"
  fi
fi

mkdir -p DakaLing.xcodeproj

if [ ! -s project.pbxproj ] || ! head -n 1 project.pbxproj | grep -q 'UTF8' || ! grep -q 'isa = PBXProject' project.pbxproj; then
  echo "找不到可用的 project.pbxproj。请把整个 ios 文件夹重新拷到 Mac，再双击这个脚本。"
  exit 1
fi

echo "正在写回工程文件。如果签名里的 Team 变空了，重新选一次你的 Apple ID。"
cp -f project.pbxproj DakaLing.xcodeproj/project.pbxproj

mkdir -p DakaLing.xcodeproj/project.xcworkspace
if [ ! -s DakaLing.xcodeproj/project.xcworkspace/contents.xcworkspacedata ]; then
  cat > DakaLing.xcodeproj/project.xcworkspace/contents.xcworkspacedata << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<Workspace
   version = "1.0">
   <FileRef
      location = "self:">
   </FileRef>
</Workspace>
EOF
fi

if [ ! -s AppIcon.png ]; then
  echo "找不到 AppIcon.png。它要和 DakaLing.xcodeproj 放在同一层。"
  exit 1
fi
png_sig=$(od -An -tx1 -N 8 AppIcon.png | tr -d ' \n')
if [ "$png_sig" != "89504e470d0a1a0a" ]; then
  echo "AppIcon.png 不是一张有效图片，actool 会报 Unable to parse empty data。"
  exit 1
fi
echo "正在重写 App 图标，清掉资源包里的空文件。"
rm -rf DakaLing/Assets.xcassets
icon_dir="DakaLing/Assets.xcassets/AppIcon.appiconset"
mkdir -p "$icon_dir"
cp -f AppIcon.png "$icon_dir/AppIcon.png"
cat > "$icon_dir/Contents.json" << 'EOF'
{
  "images" : [
    {
      "filename" : "AppIcon.png",
      "idiom" : "universal",
      "platform" : "ios",
      "size" : "1024x1024"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
EOF
printf '%s\n' '{' '  "info" : {' '    "author" : "xcode",' '    "version" : 1' '  }' '}' > DakaLing/Assets.xcassets/Contents.json
if [ ! -s "$icon_dir/AppIcon.png" ]; then
  echo "图标写进去之后仍是空的。"
  exit 1
fi

missing=0
check_file() {
  local path="$1"
  local marker="$2"
  local why="$3"
  if [ ! -s "$path" ] || ! grep -q "$marker" "$path"; then
    echo "缺少 $path 。$why"
    missing=1
  fi
}
check_file "DakaLing/Models.swift" "enum ReminderKind" "没有它，ReminderKind 会报 Cannot find type in scope。"
check_file "DakaLing/Theme.swift" "struct PunchButtonStyle" "没有它，Theme 和 PunchButtonStyle 会报 Cannot find in scope。"
check_file "DakaLing/AppModel.swift" "class AppModel" "这是提醒的主要逻辑。"
check_file "DakaLing/AlarmCurtain.swift" "struct AlarmCurtain" "这是滑动关闭的页面。"
check_file "DakaLing/AlarmFeedback.swift" "enum AlarmFeedback" "这是铃声和震动。"
if [ "$missing" -ne 0 ]; then
  echo "请把最新的整个 ios/DakaLing 文件夹再覆盖到这里。不要只拷几个 .swift，也不要只拖蓝色的工程图标。"
  exit 1
fi

echo "工程文件已就绪，正在打开 Xcode。"
open DakaLing.xcodeproj
