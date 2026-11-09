"""App icons for the store screenshots → store/app_icons/<package>.png (192 px circles).
The One family's own logos (~/one-logos) plus plain glyph icons: no third-party brands
(Play rejects listings that show other companies' logos).
Run: python3 tool/store_icons.py, then the store shots test."""
import re
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
F='/opt/homebrew/share/flutter'
src=open(F+'/packages/flutter/lib/src/material/icons.dart').read()
def cp(n): return int(re.search(r'static const IconData %s = IconData\(\s*(0x[0-9a-f]+)'%n, src).group(1),16)
font_path=F+'/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf'
OUT=Path(__file__).resolve().parent.parent/'store/app_icons'; N=192; S=4
LOGOS=Path.home()/'one-logos/png/android/xxxhdpi'
one={'com.one.chat.messaging':'one-chat','com.one.camera':'one-camera','com.one.wallet':'one-tracker','com.one.docs':'one-canvas','com.one.health':'one-watch'}
glyph={  # package: (icon, top colour, bottom colour)
 'com.one.messages':('chat_bubble','#5B8DEF','#3461D1'),'com.one.dialer':('phone','#4CC38A','#23995F'),
 'com.one.contacts':('person','#F2A65A','#D9792B'),'com.one.mail':('mail','#EF6B5B','#C9432F'),
 'com.one.calendar':('calendar_month','#5A7BEF','#3A4FC9'),'com.one.todo':('check_circle','#38B6C9','#1E8A9E'),
 'com.one.meet':('videocam','#2BB673','#178A52'),'com.one.bank':('account_balance','#3E5C76','#253A4F'),
 'com.one.pay':('payments','#7C5CE0','#5634B8'),'com.one.invest':('show_chart','#1FA971','#11784F'),
 'com.one.music':('music_note','#F0567A','#C42C55'),'com.one.photos':('photo_library','#F7B733','#E08A12'),
 'com.one.video':('smart_display','#E2493B','#B32A1F'),'com.one.podcast':('podcasts','#9B59D0','#6E33A6'),
 'com.one.shop':('shopping_bag','#F08A3C','#CC5F17'),'com.one.grocery.shop':('local_grocery_store','#6CBF4A','#47962A'),
 'com.one.maps':('map','#34A6E0','#1A78B5'),'com.one.metro':('train','#5C6BC0','#3A479A'),
 'com.one.booking':('flight','#26A69A','#147A70'),'com.one.news':('newspaper','#546E7A','#37474F'),
 'com.one.books':('menu_book','#D9822B','#AD5A10'),'com.one.chess':('extension','#8D6E63','#5D4037'),
 'com.one.puzzle':('extension','#EC6FA5','#C2427B'),'com.one.sleep':('bedtime','#4A4FB8','#2C2F85'),
 'com.one.deskclock':('schedule','#455A64','#263238'),'com.one.calculator':('calculate','#FF8A50','#E0602A'),
 'com.one.weather':('wb_sunny','#3DA5F4','#F7B733'),'com.one.files':('folder','#4F8EF7','#2B63D1'),
 'com.one.settings':('settings','#78909C','#4E626C'),
}
def hexc(h): return tuple(int(h[i:i+2],16) for i in (1,3,5))
def circle_mask(n):
    m=Image.new('L',(n*S,n*S),0); ImageDraw.Draw(m).ellipse([0,0,n*S-1,n*S-1],fill=255); return m.resize((n,n),Image.LANCZOS)
for pkg,name in one.items():
    bg=Image.open(LOGOS/f'{name}-bg.png').convert('RGBA'); fg=Image.open(LOGOS/f'{name}-fg.png').convert('RGBA')
    im=Image.alpha_composite(bg,fg); w=im.size[0]; k=w*18/108  # visible 72 of 108
    im=im.crop((int(k),int(k),int(w-k),int(w-k))).resize((N,N),Image.LANCZOS); im.putalpha(circle_mask(N)); im.save(OUT/f'{pkg}.png')
for pkg,(ic,a,b) in glyph.items():
    n=N*S; top,bot=hexc(a),hexc(b)
    g=Image.new('RGBA',(1,n))
    for y in range(n): t=y/(n-1); g.putpixel((0,y),tuple(int(top[i]+(bot[i]-top[i])*t) for i in range(3))+(255,))
    im=g.resize((n,n))
    sheen=Image.new('RGBA',(n,n),(0,0,0,0)); ImageDraw.Draw(sheen).ellipse([-n*.2,-n*.75,n*1.2,n*.42],fill=(255,255,255,34)); im=Image.alpha_composite(im,sheen)
    d=ImageDraw.Draw(im); f=ImageFont.truetype(font_path,int(n*.5)); ch=chr(cp(ic))
    l,t,r,bb=d.textbbox((0,0),ch,font=f); d.text((n/2-(l+r)/2,n/2-(t+bb)/2),ch,font=f,fill=(255,255,255,255))
    im=im.resize((N,N),Image.LANCZOS); im.putalpha(circle_mask(N)); im.save(OUT/f'{pkg}.png')
print('ok',len(list(OUT.glob('*.png'))))
