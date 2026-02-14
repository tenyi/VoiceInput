import math
from PIL import Image, ImageDraw, ImageFilter
from PIL.ImageDraw import Draw

def create_radial_gradient(width, height, center_color, edge_color, center_offset=(0.5, 0.5)):
    """創建徑向漸層"""
    base = Image.new('RGB', (width, height), edge_color)

    # 創建徑向遮罩
    mask = Image.new('L', (width, height))
    mask_data = []

    cx, cy = center_offset[0] * width, center_offset[1] * height
    max_dist = math.sqrt(((width * 0.5) ** 2) + ((height * 0.5) ** 2))

    for y in range(height):
        for x in range(width):
            dist = math.sqrt((x - cx) ** 2 + (y - cy) ** 2)
            # 徑向漸變：中心最亮，邊緣最暗
            factor = max(0, 1 - (dist / max_dist) ** 0.7)
            mask_data.append(int(255 * factor))

    mask.putdata(mask_data)

    # 創建中心顏色的圖層
    center_layer = Image.new('RGB', (width, height), center_color)

    # 應用遮罩
    result = Image.new('RGB', (width, height))
    for i in range(3):  # RGB 通道
        result.putdata(list(zip(
            [c[i] for c in base.getdata()],
            [c[i] for c in center_layer.getdata()],
            [c[i] for c in mask.getdata()]
        )))

    return result


def create_linear_gradient(width, height, start_color, end_color, direction='vertical'):
    """創建線性漸層"""
    base = Image.new('RGB', (width, height), start_color)
    top = Image.new('RGB', (width, height), end_color)
    mask = Image.new('L', (width, height))
    mask_data = []

    for y in range(height):
        for x in range(width):
            if direction == 'vertical':
                factor = y / height
            else:
                factor = x / width
            mask_data.append(int(255 * factor))

    mask.putdata(mask_data)
    base.paste(top, (0, 0), mask)
    return base


def hex_to_rgb(hex_color):
    hex_color = hex_color.lstrip('#')
    return tuple(int(hex_color[i:i+2], 16) for i in (0, 2, 4))


def draw_microphone_shiny(draw, center_x, center_y, scale):
    """繪製帶有金屬光澤效果的麥克風"""

    # 金色調色板 - 奢華金色
    gold_dark = (139, 90, 43)       # 深金色
    gold_medium = (212, 175, 55)    # 中金色
    gold_light = (255, 215, 0)      # 亮金色
    gold_highlight = (255, 255, 200) # 高光

    scale = 1.0

    # ===== 麥克風主體 =====
    body_w = 220 * scale
    body_h = 380 * scale
    body_x = center_x - body_w / 2
    body_y = center_y - body_h / 2 - 80 * scale

    # 麥克風外殼 - 橢圓形
    # 先畫陰影
    shadow_offset = 10 * scale
    draw.ellipse([body_x + shadow_offset, body_y + shadow_offset,
                  body_x + body_w + shadow_offset, body_y + body_h + shadow_offset],
                 fill=(0, 0, 0, 80))

    # 麥克風本體
    draw.ellipse([body_x, body_y, body_x + body_w, body_y + body_h * 0.25],
                 fill=gold_light, outline=gold_dark, width=int(8*scale))  # 頂部橢圓
    draw.ellipse([body_x, body_y + body_h * 0.75,
                  body_x + body_w, body_y + body_h],
                 fill=gold_dark, outline=gold_dark, width=int(8*scale))  # 底部橢圓

    # 中間矩形
    draw.rectangle([body_x, body_y + body_h * 0.125,
                    body_x + body_w, body_y + body_h * 0.875],
                   fill=gold_medium)

    # 頂部高光線
    draw.line([body_x + 20*scale, body_y + 30*scale,
               body_x + body_w - 20*scale, body_y + 30*scale],
              fill=gold_highlight, width=int(6*scale))

    # 網格線 (模擬麥克風網罩)
    grid_color = gold_dark
    # 水平線
    for i in range(1, 6):
        y = body_y + body_h * 0.2 + (body_h * 0.55 / 6) * i
        draw.line([body_x + 15*scale, y, body_x + body_w - 15*scale, y],
                  fill=grid_color, width=int(3*scale))

    # 垂直線
    for i in range(1, 6):
        x = body_x + body_w * 0.15 + (body_w * 0.7 / 6) * i
        draw.line([x, body_y + body_h * 0.2, x, body_y + body_h * 0.75],
                  fill=grid_color, width=int(3*scale))

    # ===== 麥克風支架 =====
    # U 型支架
    stand_w = 140 * scale
    stand_h = 120 * scale
    stand_x = center_x - stand_w / 2
    stand_y = body_y + body_h

    # 支架彎曲部分 - 使用兩個橢圓
    draw.arc([stand_x - 20*scale, stand_y,
              stand_x + stand_w + 20*scale, stand_y + stand_h * 2],
             start=0, end=180, fill=gold_medium, width=int(20*scale))

    # 支架橫桿
    draw.rectangle([center_x - 60*scale, stand_y + stand_h * 0.8,
                    center_x + 60*scale, stand_y + stand_h * 1.0],
                   fill=gold_medium, outline=gold_dark, width=int(4*scale))

    # ===== 底座 =====
    base_w = 200 * scale
    base_h = 30 * scale
    base_x = center_x - base_w / 2
    base_y = stand_y + stand_h * 1.5

    # 底座橢圓
    draw.ellipse([base_x, base_y, base_x + base_w, base_y + base_h],
                 fill=gold_dark, outline=gold_medium, width=int(4*scale))

    # 底座裝飾環
    draw.ellipse([base_x + 20*scale, base_y + 5*scale,
                  base_x + base_w - 20*scale, base_y + base_h - 5*scale],
                 fill=None, outline=gold_light, width=int(2*scale))


def add_gloss_effect(image):
    """添加光澤效果"""
    # 創建一個半透明的光澤層
    width, height = image.size
    overlay = Image.new('RGBA', (width, height), (0, 0, 0, 0))
    draw = Draw(overlay)

    # 添加對角線光澤
    for i in range(0, width, 4):
        alpha = int(30 * (1 - i / width))
        draw.line([(i, 0), (i + height, height)],
                  fill=(255, 255, 255, alpha))

    # 混合
    result = Image.new('RGBA', (width, height))
    result.paste(image, (0, 0))
    result.paste(overlay, (0, 0), overlay)

    return result


def main():
    size = 1024

    # 創建深色背景 + 金色徑向漸層
    bg_color = (20, 15, 10)  # 深棕黑色
    glow_color = (255, 180, 50)  # 金色光暈

    # 創建背景
    background = Image.new('RGB', (size, size), bg_color)

    # 添加徑向金色光暈
    for i in range(5):
        glow_size = int(size * (0.6 - i * 0.1))
        offset = (size - glow_size) // 2
        glow = create_radial_gradient(glow_size, glow_size,
                                       (255, 200, 80),
                                       (255, 180, 50, 0),
                                       center_offset=(0.5, 0.5))
        # 模糊處理
        glow = glow.filter(ImageFilter.GaussianBlur(radius=30))
        # 放置到背景
        background.paste(glow, (offset, offset), glow)

    # 在背景上繪製麥克風
    draw = Draw(background)
    draw_microphone_shiny(draw, size/2, size/2, 1.0)

    # 添加光澤效果
    # background = add_gloss_effect(background)

    # 保存
    background.save("AppIcon.png", "PNG", quality=100)
    print("AppIcon.png created successfully!")

    # 同時生成不同尺寸的圖示
    sizes = [16, 32, 64, 128, 256, 512]
    for s in sizes:
        resized = background.resize((s, s), Image.Resampling.LANCZOS)
        resized.save(f"AppIcon_{s}x{s}.png", "PNG")
        print(f"AppIcon_{s}x{s}.png created!")


if __name__ == "__main__":
    main()
