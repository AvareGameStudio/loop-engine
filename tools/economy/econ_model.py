"""Heist-income vs cash-sink model behind the price ladders in GameState/MetaUpgrade.
A greedy player buys the cheapest affordable sink after every heist; a night away (8 h of
Crew) lands every 10 heists. Run: python3 tools/economy/econ_model.py
Prints the heist the hideout shelf fills and any heist with 3+ purchases at once."""
import math,sys
# income per heist h (doors 3h-2..3h, pins), x1.3 for hot hands / golden, x loot bonus
def income(h, items):
    doors=sum(40+12*s for s in range(3*h-2,3*h+1))
    pins=13*(2+(3*h)//5)*1.15
    return (doors+pins)*1.3*(1+0.02*items)
def run(cfg, H=60, verbose=False):
    loot=lambda slot: round(cfg["lb"]*cfg["lg"]**(slot-3)/50)*50
    gloves=sorted(cfg["gloves"])
    gate=[round(cfg["gb"]*cfg["gg"]**i) for i in range(4)]
    crew=lambda lvl: round(cfg["cb"]*cfg["cg"]**(lvl-1))
    cash=0; items=3; gl=0; gt=0; cl=1; log=[]; maxratio=0; hoard=[]
    for h in range(1,H+1):
        cash+=income(h,items)
        if h>=5 and h%cfg.get("night",1000)==0: cash+=cfg["crew_h"]*8*income(h,items)/1.3*(1+0.25*(cl-1))
        bought=[]
        while True:
            opts=[]
            if h>=3 and items<12: opts.append(("loot",loot(items)))
            if h>=3 and gl<len(gloves): opts.append(("glove",gloves[gl]))
            if h>=3 and gt<4: opts.append(("gate",gate[gt]))
            if h>=5: opts.append(("crew",crew(cl)))
            if not opts: break
            k,p=min(opts,key=lambda o:o[1])
            if cash<p: break
            cash-=p; bought.append(k)
            if k=="loot": items+=1
            elif k=="glove": gl+=1
            elif k=="gate": gt+=1
            else: cl+=1
        if len(bought)>=3: hoard.append((h,len(bought)))
        log.append((h,int(cash),items,gl,gt,cl,",".join(bought)))
    if verbose:
        for r in log: print(*r)
    full=[r[0] for r in log if r[2]==12]
    return full[0] if full else None, hoard, log[29]

if __name__ == "__main__":
    live=dict(lb=2000,lg=1.55,gloves=[800,1500,2500,4000,6000],gb=1500,gg=2.0,cb=2500,cg=1.7,crew_h=0.5,night=10)
    full,bursts,_=run(live,H=80)
    print("shelf full at heist",full,"| 3+ buys at once:",bursts)
    run(live,H=50,verbose=True)
