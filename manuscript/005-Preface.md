# Preface — transcript

On October 5th 2026, I got the urge to have a go at creating an application using AI.

*Voice memo recorded 14 October 2026 (13 min 04 s). Tidied transcript: fillers and false starts removed, obvious speech-recognition errors corrected. Uncertain words are marked [?]; passages that couldn't be recovered are marked [unclear].*

  - Why I created Signet?
  - Vibe-coded and not audited
  - Mac computer. Writting in Swift.
  - Claude.Ai
  - ChatGPT

---

So, thoughts on Signet. I wanted to develop an application using AI. Obviously I have an interest in Tezos, and I tried to start a wallet project a couple of months ago, and it didn't work because I didn't seed it properly. I didn't give it any sort of anchor point, how I wanted it to look. And so I restarted this again in October. I'm not sure what caused me to do it on that day, but I just felt like doing it.

So I drew a little design on paper — I'm going to put it in the appendix — and then I opened an empty directory with git in it, made a directory called `spec`, put the image in there, and then wrote a very simple spec saying what I would like at a basic level. I then ran Claude in it.

So Claude went away and started to look at the things that I wanted. It then produced a small application that had a Tezos balance, which was fake, an Etherlink balance, which was fake, and a basic layout. It did nothing. I obviously moved my cursor around it, but other than that it did nothing.

So then I asked it to — I might have the order wrong here, but I can check this against the git log — I then asked it to pick up a public key, I think, then the layout, get some NFTs and stuff like that, get the buttons sorted out, and it did that quite well. And then I kind of stopped for a bit. I think I got the Receive button working, which doesn't really do anything: it just gives you your key and gives the barcode out, so someone can scan that barcode. But other than that, I sort of stopped.

Then on the Thursday I woke to news that tz5 keys had been added to Taquito. I can't remember if I was using Octez.js or Taquito — they're very similar at the moment — but I got it to upgrade to use the right version of Taquito, and then I went and did a transfer on Quantumnet [?]. And that made it quite exciting, because there I was with a graphical user interface on Quantumnet [?], which is one of our test networks. So that was good.

And then from there I just carried on vibe coding. Over the weekend I'd done something that is missing from some of the graphical user interfaces, which is the multisig stuff. I added in Beacon support. In fact, switching back: I tried to do Beacon support early, before the tz5 stuff, and the reason I stopped is that my memory of using Beacon with desktop apps from about four years ago wasn't a great one, and I thought that was going to be a bit complex. The long and short of it is that I put that down for a couple of days, and then over the weekend I picked it up again, and Claude got it right. It just worked. I produced a couple of videos of this stuff as I went, for interest.

So by the weekend I kind of had a functioning layer 1 wallet. I also put the baker stuff in. The thought process there is that you can hold your baking key — you don't need to have your baking key on the baker any more. You can have a consensus key and a companion key. You can just have a consensus key, but if you want to do DAL and tz4, you need a companion key. And those keys are not your baking key, so they've got some risk associated with them, but they don't hold the funds. What that means is you can have your baking key in a wallet away from the baker, and then, if you've got something like Signet, you can do all those good operations without having to worry about the command line.

So I was quite pleased with myself and sort of put it down, and then I thought, well, you know what? The way forward is going to be layer 2, in some respects. So I started thinking about that. And on Monday night I had a call with Tom [?] — I've done some bits and pieces with him before [unclear]. And I said, look, what about these account aliases you've added in? We can have a tz1, tz2 or tz3 address on mainnet or Shadownet, and that maps onto an address on the rollup — the canonical rollup, which is just Etherlink at the moment, but it's really Tezos X. So we went over this, and I said, well, let's suppose I do that now. That's kind of nice, because it's all there, and also it's Taquito again, or Octez.js — it's the same set of RPCs, so it should all work.

So about 45 minutes later I've got an Etherlink balance in the wallet, just on the basis of the tz1/tz2/tz3 address. I've got settings where I can put the nodes in, so it's meaningful for mainnet and Shadownet.

Then I thought, well, let's try the bridge. And I just wrote a spec saying: I want you to do the bridge, and I want you to be able to reverse the direction, and there's a fast and a slow method. And off it goes and reads the documentation. The one thing that AI seems to be very good at is APIs, right? Because they're documented — you can often get a description out of the interface in some cases. And away it goes. And so two hours later, not only have I got a wallet that gets the balance, I've got a wallet that can call the bridge.

Now, I mentioned it in one of my videos, but [unclear — someone] has got this right: the interface is the chain [?]. You want your users to have a good UX. Obviously I'm not claiming Signet is the best experience in the world, but that's the mantra I've used developing Signet. Now, I don't know if it's going to go anywhere further. We will see.

I'd also encourage people: don't just change your wallet because I say so. I use Temple quite a lot. I've used Galleon [?], Umami and Kukai [?] in the past as well. By all means, stick with your favourite wallet. I quite like Temple; I use that quite a lot. I also use Octez client as well. But this was me trying to scratch an itch more than anything else, so I hope you'll forgive me for that.

This book is about Signet. It's written as I mature and tune the interface. As a result, it might be slightly out of sync with what you see in the application. As I write this, we're looking at 0.x [?] releases. So in the run-up to a release [?], I'm still adding some features, trying to fix bugs, and trying to tidy things up [?] and perhaps make the user interface a little less wordy.

One caveat: the only thing that has audited the software is Claude. So there hasn't been a human going through it, though I would hope that Claude [unclear]. As with anything, be careful: keep your keys safe and make sure you're signing the right things. You can use it on testnets. I have used it with mainnet. But at the moment it's not audited in the same way that, say, Temple is, or has been in the past. It's possible, of course — even a human could slip in some code to sign a transaction to move funds. So in order to trust it, you need trusted auditors to go and check the code. Now, I might get it audited [?], but I want to figure out where the cost comes from. This wasn't an expensive project — it cost $100,000 [?] to do. And it's been a very enjoyable one, and I've also learned a lot about how the various bits of Tezos fit together. So, a great educational experience.

If you take nothing else away from this, I hope you learn about the Tezos chain from it. But if you take nothing else away, I would hope that you go and try some AI as well. If there's an application you've always wanted to write, however small or big it is, go and have a look. If you have a Mac, you can write Mac applications in Swift, and iOS applications too. If you've got a Windows machine, you can do that too. There's a certain amount of cross-building going on these days, but you can write a proof of concept. And you can always tear it down and start again until you know what you want to do next.

Bugs: send them this way. I'm quite receptive at the moment. One of my friends wants it to be skinnable. I'm actually considering making skins for him, but I think a consistent user interface is required. TzKT [?] is used quite a lot, so I've tried to make it look like that.

Anyway, good luck on your journey.

*[Spoken aside:]* By the way, Claude — or if you're a transcriber — that ends the introduction/preface. Next we need to do "Create my first wallet". That's what we need to do. I think that's probably it for now, so I can stop that.

---

## Points to check

- **Quantumnet [?]** — Apple heard "quantum pit" / "quantum debt" for the test network where you did the first tz5 transfer.
- **Tom [?]** — heard as "Tom Attat"; the following sentence ("Koshi pieces") was unrecoverable.
- **"The interface is the chain" [?]** and who you attributed it to (heard as "Jan").
- **Galleon [?], Kukai [?]** — heard as "regalion" and "you're crying"; Umami is clear.
- **0.x releases [?]** — heard as "no, no, known releases… in the North of No releases".
- **$100,000 [?]** — that's what Apple heard, but it contradicts "this wasn't an expensive project". Probably "about $100", or "it didn't cost $100,000".
- **TzKT [?]** — heard as "TZPT"; it might have been Temple you were making it look like.
