#!/usr/bin/env python3
# 生成 Steam 商店素材图（程序化绘制，萝卜/厨房主题）。
# 尺寸遵循 Steam 后台要求：capsule 616x353 / header 460x215 / screenshot 1280x720 / background 1280x720。
# 非真实游戏截图（Web 构建无法自动抓帧），而是风格化占位图，可直接上传商店页。
import os, math
from PIL import Image, ImageDraw, ImageFont

OUT = "/workspace/veggie-arena/web/store-assets"
os.makedirs(OUT, exist_ok=True)

CREAM=(244,241,232); SKIN=(247,210,78); LEAF=(90,170,77); LEAF2=(69,140,62)
EN_RED=(224,96,95); EN_PUR=(154,122,208); EN_CY=(86,207,224); EN_GRN=(90,138,74)
DARK=(20,22,30); PANEL=(30,34,44); GOLD=(250,212,76); WOK=(224,122,58)

def font(sz):
    for p in ["/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
              "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"]:
        if os.path.exists(p):
            return ImageFont.truetype(p, sz)
    return ImageFont.load_default()

def bg(w,h,c1,c2):
    img=Image.new("RGB",(w,h),c1); d=ImageDraw.Draw(img)
    for y in range(h):
        t=y/h
        d.line([(0,y),(w,y)],fill=tuple(int(c1[i]+(c2[i]-c1[i])*t) for i in range(3)))
    return img

def turnip(d,cx,cy,s,body=CREAM):
    d.ellipse([cx-s*0.5,cy-s*0.7,cx+s*0.5,cy+s*0.8],fill=body)
    d.ellipse([cx-s*0.3,cy-s*0.35,cx+s*0.3,cy+s*0.1],fill=(255,255,255))
    d.ellipse([cx-s*0.18,cy-s*0.15,cx-s*0.08,cy-s*0.02],fill=DARK)
    d.ellipse([cx+s*0.08,cy-s*0.15,cx+s*0.18,cy-s*0.02],fill=DARK)
    d.polygon([(cx,cy-s*0.7),(cx-s*0.35,cy-s*1.15),(cx-s*0.05,cy-s*0.85)],fill=LEAF)
    d.polygon([(cx,cy-s*0.7),(cx+s*0.35,cy-s*1.15),(cx+s*0.05,cy-s*0.85)],fill=LEAF2)
    d.polygon([(cx,cy-s*0.7),(cx,cy-s*1.25),(cx-s*0.1,cy-s*0.9)],fill=LEAF)

def enemy(d,cx,cy,r,c):
    d.ellipse([cx-r,cy-r,cx+r,cy+r],fill=c)
    d.ellipse([cx-r*0.4,cy-r*0.4,cx-r*0.1,cy-r*0.1],fill=DARK)
    d.ellipse([cx+r*0.1,cy-r*0.4,cx+r*0.4,cy-r*0.1],fill=DARK)

def title(img,text,sz,c,y):
    d=ImageDraw.Draw(img); f=font(sz)
    bb=d.textbbox((0,0),text,font=f); w=bb[2]-bb[0]
    d.text(((img.width-w)/2,y),text,fill=c,font=f)

def hud(d,w):
    d.rectangle([40,w-90,420,w-30],fill=PANEL)
    d.text((60,w-80),"WAVE 7",fill=GOLD,font=font(28))
    d.text((220,w-80),"HP 80",fill=(230,120,120),font=font(24))
    d.text((340,w-80),"GOLD 240",fill=GOLD,font=font(24))

# 1) capsule 616x353
img=bg(616,353,(40,30,30),(90,60,40)); d=ImageDraw.Draw(img)
turnip(d,200,200,120); enemy(d,430,150,40,EN_RED); enemy(d,500,230,30,EN_PUR); enemy(d,460,280,34,EN_CY)
title(img,"TURNIP TROUBLE",34,(250,230,120),290); img.save(f"{OUT}/capsule_616x353.png")

# 2) header 460x215
img=bg(460,215,(30,24,40),(70,50,80)); d=ImageDraw.Draw(img)
turnip(d,120,120,90); enemy(d,330,90,28,EN_RED); enemy(d,370,150,24,EN_CY)
title(img,"TURNIP TROUBLE",24,(250,230,120),172); img.save(f"{OUT}/header_460x215.png")

# 3) screenshot 01 title
img=bg(1280,720,(30,26,40),(60,50,80)); d=ImageDraw.Draw(img)
turnip(d,640,340,200)
title(img,"TURNIP TROUBLE",64,(250,230,120),120)
title(img,"A kitchen arena survivor",28,(220,220,230),210)
title(img,"PRESS START",30,GOLD,560); img.save(f"{OUT}/screenshot_01_title.png")

# 4) screenshot 02 combat
img=bg(1280,720,(28,28,38),(55,55,70)); d=ImageDraw.Draw(img)
turnip(d,640,400,170)
for i in range(8):
    a=i/8*6.28; enemy(d,int(640+math.cos(a)*260),int(400+math.sin(a)*200),36,[EN_RED,EN_PUR,EN_CY,EN_GRN][i%4])
for i in range(6):
    d.ellipse([300+i*40,360,308+i*40,368],fill=SKIN)
hud(d,720); title(img,"WAVE 7 - FIGHT",30,GOLD,40); img.save(f"{OUT}/screenshot_02_combat.png")

# 5) screenshot 03 shop
img=bg(1280,720,(35,30,45),(60,55,75)); d=ImageDraw.Draw(img)
for i in range(4):
    x=140+i*280; d.rectangle([x,180,x+240,360],fill=PANEL)
    d.text((x+20,200),["PAN","FORK","GRATER","MICROW"][i],fill=GOLD,font=font(26)); turnip(d,x+120,300,60)
title(img,"SUPPLY STATION",40,GOLD,90); img.save(f"{OUT}/screenshot_03_shop.png")

# 6) screenshot 04 characters
img=bg(1280,720,(30,32,42),(58,60,78)); d=ImageDraw.Draw(img)
cols=[CREAM,(201,162,92),(226,74,60),(215,38,61)]
for i in range(4):
    x=160+i*280; d.rectangle([x,200,x+220,440],fill=PANEL); turnip(d,x+110,330,90,cols[i])
    d.text((x+30,440),["TURNIP","POTATO","TOMATO","CHILI"][i],fill=(230,230,240),font=font(22))
title(img,"CHOOSE YOUR VEGGIE",40,GOLD,100); img.save(f"{OUT}/screenshot_04_characters.png")

# 7) screenshot 05 boss
img=bg(1280,720,(40,20,30),(80,40,50)); d=ImageDraw.Draw(img)
enemy(d,640,360,120,EN_RED)
for i in range(10):
    a=i/10*6.28; enemy(d,int(640+math.cos(a)*200),int(360+math.sin(a)*150),26,EN_PUR)
d.ellipse([560,300,720,420],outline=GOLD,width=8)
title(img,"BOSS WAVE",44,GOLD,80); img.save(f"{OUT}/screenshot_05_boss.png")

# 8) background 1280x720 (暗色水印，用于商店背景)
img=bg(1280,720,(18,18,26),(40,38,52)); d=ImageDraw.Draw(img)
for i in range(12):
    a=i/12*6.28; turnip(d,int(640+math.cos(a)*400),int(360+math.sin(a)*300),50,(60,60,70))
img.save(f"{OUT}/background_1280x720.png")

print("generated:", sorted(os.listdir(OUT)))
