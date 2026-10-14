# Reborn source catalogue

What each content source offers, its licence, whether Reborn can use it, and how the pipeline
fetches it. The rule for the core library: **only sources whose licence allows reuse in a
commercial app** (public domain, CC0, CC BY, CC BY-SA, UK OGL). Anything non-commercial (NC) is
out, because the app may charge or show ads. "Free to read" sources are summarise-only
(`original-summary` cards: our own words, a link back, no quotes).

Every card records its source, link and licence (see [SCHEMA.md](SCHEMA.md)); the registry in
[pipeline/sources.toml](pipeline/sources.toml) records how each source was fetched. This is not legal
advice: the plan's step of having an IP lawyer review the content policy before launch still stands.

Status key: **in use** (cards in `library/`), **next** (usable, not ingested yet), **excluded**,
**summarise only**. "Checked" means the licence was read from the source itself on 2026-10-10;
"to check" means it comes from general knowledge and needs confirming before use.

## What changed from the plan

1. **Most OpenStax books are now CC BY-NC-SA 4.0, so they are excluded.** The plan listed OpenStax
   as CC BY 4.0. The current sources on GitHub say otherwise (checked with
   `python -m reborn_content licences`):

   | OpenStax book | Licence now |
   |---|---|
   | Psychology 2e | CC BY-NC-SA 4.0 |
   | Introduction to Business 2e | CC BY-NC-SA 4.0 |
   | Principles of Management | CC BY-NC-SA 4.0 |
   | Organizational Behavior | CC BY-NC-SA 4.0 |
   | Entrepreneurship | CC BY-NC-SA 4.0 |
   | Principles of Finance 2e | CC BY-NC-SA 4.0 |
   | Lifespan Development | CC BY-NC-SA 4.0 |
   | College Success 2e | CC BY-NC-SA 4.0 |
   | Life, Liberty, and the Pursuit of Happiness | CC BY 4.0 (usable, but civics, not a priority) |

   Earlier editions of some of these were published under CC BY 4.0, and a CC licence can't be
   withdrawn from copies already released under it. Using a pinned older edition is possible in
   principle but needs the lawyer's sign-off and proof of which version carried which licence.
   Until then, psychology, business and emotional-intelligence cards come from public-domain books
   and the CC BY replacements listed under "next" below.
2. **NHS content is OGL, with extra terms.** The nhs.uk terms (section 3) release content under
   OGL v3.0 but add conditions: adapted content must carry the standard OGL credit ("Contains public
   sector information licensed under the Open Government Licence v3.0.") and must *not* be credited
   to the NHS website, must not imply NHS endorsement, and NHS content must not be sold as a
   separately charged item. Our NHS cards follow this.
3. **MedlinePlus is only partly public domain.** NLM-written health topic pages are public domain;
   the A.D.A.M. Medical Encyclopedia and drug monographs on the same site are copyrighted. We only
   use NLM health topic pages.

## In use

| Source | What it offers | Licence | How we fetch it | Cards from it |
|---|---|---|---|---|
| [Standard Ebooks](https://standardebooks.org) | Carefully proofread public-domain classics: Stoics, Seneca, Thoreau, Emerson, Franklin, Sun Tzu, Machiavelli, Gibran, Aesop, Booker T. Washington, Equiano | Public domain text; Standard Ebooks' own work is CC0. Checked (`dc:rights` in each book) | `standardebooks` adapter: XHTML from `github.com/standardebooks/<repo>` | Stoics, philosophy, business and money, personal development |
| [Project Gutenberg](https://www.gutenberg.org) | 75,000+ public-domain books, including self-help classics not on Standard Ebooks (James Allen, Arnold Bennett, Samuel Smiles, Wattles, Carnegie & Esenwein) | Public domain in the US; licence header checked per book. Copyrighted Gutenberg ebooks are refused by the adapter | `gutenberg` adapter: plain text from gutenberg.org, falling back to the GITenberg mirror on GitHub | Personal development, productivity, money, speaking, wisdom |
| [MedlinePlus](https://medlineplus.gov) (US National Library of Medicine) | Plain-language health topic pages (sleep, stress, exercise, nutrition) | Public domain for NLM-written pages; credit "Source: MedlinePlus, National Library of Medicine". Checked ([using content](https://medlineplus.gov/about/using/usingcontent/)) | `web`: read by hand, cards in our own words, no quotes | Health |
| [NIMH](https://www.nimh.nih.gov) | Mental-health fact sheets (stress, anxiety, depression) | Public domain US government work, to check per page | `web` | Health |
| [CDC](https://www.cdc.gov) | Physical activity, sleep, nutrition guidance | Mostly public domain; some images and partner content are not. To check per page | `web` | Health |
| King James Bible: Book of Proverbs ([Gutenberg #8020](https://www.gutenberg.org/ebooks/8020)) | Short maxims on wisdom, work, planning, money, speech and friendship | Public domain in the US and most countries. In the UK the KJV text is still under Crown letters patent, which covers printing the Bible; short quotations are generally accepted. Lawyer to confirm for UK distribution | `gutenberg` adapter with `verses = "Proverbs"`: one passage per verse, locators like "Proverbs 6:6" | Productivity, business, money, relationships, emotional intelligence |
| [Wikisource](https://en.wikisource.org) | Seneca's *Moral Letters to Lucilius* (Gummere's 1917–25 Loeb translation; translator died 1920) | Public domain | `web`: read by hand, no quotes until a Wikisource adapter exists | Mindfulness, money, relationships |
| [NHS](https://www.nhs.uk) | Mental wellbeing guides, breathing exercises, Live Well, mental-health self-help, grief and bereavement (incl. children, stillbirth, miscarriage) | OGL v3.0 plus the nhs.uk terms above. Checked ([terms](https://www.nhs.uk/our-policies/terms-and-conditions/)) | `web` | Health, mindfulness, grief & loss |
| More Gutenberg and Standard Ebooks titles (added 2026-10-11) | Ecclesiastes (KJV), Legge's *Tao Te Ching*, Carus's *The Gospel of Buddha*, Plutarch's *Lives* (Dryden/Clough), Xenophon's *Cyropaedia*, Reynolds' *Seven Discourses on Art*, Stevenson's *Essays in the Art of Writing*, Dewey's *How We Think*, William James' *Talks to Teachers*, *Dr. Montessori's Own Handbook*, Bennett's *Mental Efficiency* | Public domain; licence header checked per book | `gutenberg` (with `prefer_mirror = true`, so CI reads the same GITenberg edition the quotes were checked against) and `standardebooks` adapters, quotes verified | Faith & wisdom, lives & history, leadership, creativity, learning, study, skills, parenting, mental strength |
| [CDC](https://www.cdc.gov) Healthy Living and Positive Parenting Tips | Everyday health habits; parenting tips by child age | Public domain US government work; credit and no-endorsement line | `web` | Health, parenting |
| [NIH News in Health](https://newsinhealth.nih.gov) | Readable health articles | Public domain US government work | `web` | Health |
| [OASH womenshealth.gov](https://www.womenshealth.gov) | Healthy relationships and safety | Public domain US government work | `web` | Dating & marriage |
| HHS Children's Bureau, *The Importance of Fathers in the Healthy Development of Children* | Fathers' role in child development | US government work; summarised in our own words because the reuse statement for fatherhood.gov was unclear | `summary` | Parenting |
| [NCI PDQ](https://www.cancer.gov/about-cancer/advanced-cancer/caregivers/planning/bereavement-pdq) *Grief, Bereavement, and Loss* (patient version) | Grief, prolonged grief, grief in children | Public domain; PDQ text may be reused freely ([copyright and reuse](https://www.cancer.gov/policies/copyright-reuse)) | `web` | Grief & loss |
| Inventors, scientists and great thinkers (added 2026-10-12) | Edison: His Life and Inventions (Dyer & Martin), Darwin's *Autobiography*, Thompson's *Michael Faraday*, the Wrights' *Early History of the Airplane*, Marie Curie's *Pierre Curie*, Leonardo's *Notebooks* (Richter), Poincaré's *Foundations of Science* (Halsted), Carnegie's *Autobiography*, Bacon's *Essays*, Montaigne's *Essays* (Cotton), Nightingale's *Notes on Nursing*, Helen Keller's *The Story of My Life* | Public domain; licence header checked per book. *Pierre Curie* (Kellogg translation) and *The Story of My Life* are public domain in the US but may still be in copyright in life+70 countries, like Clason | `gutenberg` (gutenberg.org, falling back to its gutenberg.pglaf.org mirror), quotes verified | Creativity, learning, lives & history, entrepreneurship, leadership, grief & loss, dating & marriage, health |
| Nikola Tesla, *My Inventions* (1919) on [Wikisource](https://en.wikisource.org/wiki/My_Inventions) | Tesla's own account of how he invented | Public domain worldwide (Tesla d. 1943) | `web`: read by hand, no quotes | Creativity, mental strength, learning |
| Etiquette & Manners classics (added 2026-10-12) | Emily Post's *Etiquette* (1922), Chesterfield's *Letters to His Son*, Washington's *Rules of Civility* (Conway ed.), Henney's *The Book of Business Etiquette* (1922) | Public domain; licence header checked per book. Post (d. 1960) and Henney (d. 1973) are public domain in the US only | `gutenberg`, quotes verified | Etiquette, communication, business |
| Open-access research (added 2026-10-12) | Weinstein, Madan & Sumeracki 2018 *Teaching the science of learning*; Holt-Lunstad et al. 2010 *Social Relationships and Mortality Risk*; Scott et al. 2021 *Improving sleep quality leads to better mental health*; Thomson et al. 2022 on income and mental health; Burrell & Selman 2022 on funeral practices and grief | CC BY 4.0, read from each article's licence statement (PMC / Europe PMC full text). Rejected as NC or ND: Killingsworth 2021 and 2023 (PNAS), Noetel 2024 (BMJ), Singh 2023 (BJSM), Curry 2018 (JESP) | `web`: findings in our own words, no quotes | Study smarter, health, relationships, money, grief & loss |
| Kings, kingdoms and generals (added 2026-10-12) | Caesar's *Gallic War* and *Civil War*, Xenophon's *Anabasis*, Herodotus (vol. 1), Thucydides, Arrian's *Anabasis of Alexander*, Clausewitz's *On War*, the *Bābur-nāma*, Dubois's *Timbuctoo the Mysterious* (Mali and Songhai), Nitobe's *Bushido*, Gibbon's *Decline and Fall* (vol. 1), Einhard's *Life of Charlemagne*; A. T. Bryant's *Olden Times in Zululand and Natal* (1929) for Shaka Zulu | Public domain; Gutenberg licence header checked per book. Bryant died in 1953, so his book is public domain in the US and life+70 countries | `gutenberg`, quotes verified; Bryant is a `web` source read from the [Internet Archive scan](https://archive.org/details/bryant-a-t-olden-times-in-zululand-and-natal-containing-earlier-political-histor), no quotes | Lives & history, leadership |

## Next: usable, not ingested yet

These fit the licence rule and fill gaps. Each needs a registry entry and either a new adapter or
a `web` entry.

| Source | What it offers | Licence | How to fetch | Fills |
|---|---|---|---|---|
| More Gutenberg / Standard Ebooks titles | Seneca's *Letters* (Gummere), Plutarch, Montaigne, Franklin's *The Way to Wealth*, Russell Conwell's *Acres of Diamonds*, Orison Swett Marden, Florence Nightingale's *Notes on Nursing*, William James' *Talks to Teachers* ("The Gospel of Relaxation", habit), Dale Carnegie's pre-1929 works, Clason's *The Richest Man in Babylon* (1926, public domain in the US since 2022; still in copyright in some countries) | Public domain (US; check life+70 countries for 20th-century authors) | Existing adapters; add entries | Money, psychology, health history |
| African authors in the public domain | Olaudah Equiano (in use), Sol Plaatje *Native Life in South Africa* (1916), J. E. Casely Hayford *Ethiopia Unbound* (1911), Edward Wilmot Blyden, Ignatius Sancho's letters, Phillis Wheatley | Public domain (to check per title) | Gutenberg / Wikisource | The plan's African-authors angle |
| [African Storybook](https://www.africanstorybook.org) | Thousands of short stories in 200+ African languages | Mostly CC BY 4.0 (to check per story; a few are NC) | Website / API, per-story licence | Local-language content |
| US consumer finance: [CFPB](https://www.consumerfinance.gov), [Investor.gov](https://www.investor.gov) (SEC), [FDIC Money Smart](https://www.fdic.gov/consumer-resource-center/money-smart) | Budgeting, saving, debt, investing basics, compound interest | Public domain US government works (to check; some images are licensed) | `web` | Money (currently thin) |
| [SBA](https://www.sba.gov) | Starting and running a small business | Public domain US government work (to check) | `web` | Business |
| [NIH News in Health](https://newsinhealth.nih.gov), [NIA](https://www.nia.nih.gov), [NCCIH](https://www.nccih.nih.gov), [MyPlate](https://www.myplate.gov) (USDA) | Readable health articles: sleep, ageing, mindfulness, nutrition | Public domain US government works (to check) | `web` | Health |
| [PubMed Central open-access subset](https://www.ncbi.nlm.nih.gov/pmc/tools/openftlist/) | Research on wellbeing, habits, emotional intelligence | Per article; filter to CC BY / CC0 using the OA file list's licence column (it lists CC BY-NC articles too) | OA web service / FTP file list, licence filter in the adapter | Psychology, health evidence |
| [PLOS](https://plos.org) journals | Peer-reviewed studies (PLOS ONE, PLOS Medicine) | All CC BY 4.0 | PLOS API (`api.plos.org`) | Psychology, health |
| [DOAJ](https://doaj.org) | Index of open-access journals | Per journal/article; filter to CC BY | DOAJ API with licence filter | Psychology, business |
| [BCcampus Open Textbooks](https://collection.bccampus.ca), [Open Textbook Library](https://open.umn.edu/opentextbooks) | Open textbooks; e.g. *Introduction to Psychology – 1st Canadian Edition* (Jennings & Stangor) is listed as CC BY 4.0 | Varies per book; many are CC BY-NC-SA, so filter per title (to check) | Pressbooks export (EPUB/XHTML) | Psychology, business (OpenStax replacement) |
| [GOV.UK](https://www.gov.uk) and other UK public bodies | Money, work and health guidance | OGL v3.0 (to check per page) | `web` | Money, career |
| [Wikisource](https://en.wikisource.org) | Public-domain texts not on Gutenberg | Public domain texts; Wikisource's own additions are CC BY-SA | MediaWiki API | Rare PD works |

## Usable with conditions

| Source | Condition | Decision |
|---|---|---|
| [Wikipedia](https://en.wikipedia.org) | CC BY-SA 4.0: credit, and cards adapted from it must be shared under CC BY-SA too | Allowed (`cc-by-sa-4.0`), but use sparingly: those cards carry share-alike, and Wikipedia is better as background for the AI agent than as card text |
| Project Gutenberg trademark | Public-domain texts are free to reuse; the "Project Gutenberg" name is a trademark and its licence restricts using it on derived products | We credit "Project Gutenberg" only as where the public-domain text was found. Lawyer to confirm the credit wording |
| 20th-century public-domain books | Public domain in the US (published before 1931 as of 2026) can still be in copyright in life+70 countries | Prefer authors who died before 1956; flag others in the source `notes` |

## Excluded

| Source | Why |
|---|---|
| OpenStax (most books, see above) | CC BY-NC-SA 4.0 now |
| [WHO](https://www.who.int) | Mostly CC BY-NC-SA 3.0 IGO: non-commercial |
| [LibreTexts](https://libretexts.org) | Mostly CC BY-NC-SA; only individual CC BY pages would qualify |
| [MIT OpenCourseWare](https://ocw.mit.edu) | CC BY-NC-SA |
| [Noba Project](https://nobaproject.com) | CC BY-NC-SA |
| TED talks | CC BY-NC-ND: summarise only |
| MedlinePlus A.D.A.M. encyclopedia, drug monographs | Copyrighted, licensed to NLM |
| Deepstash, Blinkist, other apps' cards | Never copy; the plan forbids it |
| NHS Every Mind Matters | All rights reserved and no commercial use, unlike the main nhs.uk pages; we use the nhs.uk mental-health self-help pages instead |
| NIA (nia.nih.gov) articles | Public domain, but the article pages could not be fetched; NCI's PDQ grief summary is used instead |

## Summarise only (`original-summary`)

Free to read, not to copy. Cards are written in our own words from someone who read or watched
the source, credit the author, link back, and carry no quotes. Good candidates for Phase 5:

- Modern bestsellers: *Atomic Habits*, *Deep Work*, *Thinking, Fast and Slow*, *Emotional
  Intelligence* (Goleman), *The Psychology of Money*, *Mindset* (Dweck), *Man's Search for Meaning*.
- Articles: Harvard Business Review, Psychology Today, Greater Good Science Center (Berkeley),
  Harvard Health, Farnam Street.
- Talks and podcasts: TED, Huberman Lab, Hidden Brain, The Knowledge Project.
- African voices: Chimamanda Ngozi Adichie's talks, Chinua Achebe, Wangari Maathai's *Unbowed*,
  Tony Elumelu Foundation and Africa-focused business writing.

**In use:** The Richest Man in Babylon (Clason), Think and Grow Rich (Hill), Eat That Frog! (Tracy),
The 48 Laws of Power (Greene), Atomic Habits (Clear), Mini Habits (Guise), How to Win Friends and
Influence People (Carnegie), Deep Work, Essentialism, The 7 Habits of Highly Effective People,
Thinking, Fast and Slow, Mindset, Man's Search for Meaning, Emotional Intelligence, Why We Sleep,
The Psychology of Money, Rich Dad Poor Dad, Crucial Conversations, The 5 Love Languages, Chinua
Achebe's The Education of a British-Protected Child, Tony Elumelu's Africapitalism, Strive
Masiyiwa's mentoring posts and talks, Zero to One (Thiel & Masters), and Anaïs Nin's Diary, In Favor of the Sensitive Man and The
Novel of the Future (her erotica is excluded); and, for the new categories, The Seven Principles for Making Marriage Work (Gottman), Attached (Levine & Heller), How to Talk So Kids Will Listen (Faber & Mazlish), Grit (Duckworth), Make It Stick (Brown, Roediger & McDaniel), A Mind for Numbers (Oakley), Getting Past Your Breakup (Elliott), Rebuilding (Fisher & Alberti), Peak (Ericsson & Pool), Ultralearning (Young) and It's OK That You're Not OK (Devine). *How to Win Friends* (1936, renewed) is in copyright in the US until
2032 but public domain since 2026 in life+70 countries (Carnegie died 1955). They are registered in
`sources.toml` with `adapter = "summary"`. *The Richest Man in Babylon* (1926) has been public
domain in the US since 2022, but Clason died in 1957, so it is in copyright until the end of 2027 in
life+70 countries (UK, EU, Nigeria). *Think and Grow Rich* (1937) is sometimes called public domain
in the US for lack of a renewal; that is unconfirmed, and Hill died in 1970. Both are summaries for
now so the cards are safe in every country.

With 30 cards for each summarised book (Moses' decision, 2026-10-10), cards stick to the book's
key ideas in our own words and never walk through it chapter by chapter. Thin books stop at the
honest number of distinct ideas rather than padding.

The pipeline has no adapter for these on purpose: nothing is fetched or stored. Cards are written
by hand and the validator rejects any `quote` on them.

## The pipeline

Code lives in [pipeline/](pipeline/). Python 3.11+, standard library only.

```sh
cd content/pipeline
python -m reborn_content fetch            # download sources into build/passages/<id>.jsonl (licence-checked)
python -m reborn_content validate         # check library/*.json against SCHEMA.md and the registry
python -m reborn_content verify           # check every quote appears verbatim in its source
python -m reborn_content licences         # re-check upstream licences of candidate sources (OpenStax)
python -m reborn_content export           # build/rag/{cards,passages}.jsonl for the AI agent
python -m reborn_content stats --markdown # regenerate LIBRARY.md
python -m unittest -v                     # offline tests
```

`fetch` re-reads each source's licence upstream (Standard Ebooks `dc:rights`, the Gutenberg
licence header, OpenStax `md:license`) and stops if it differs from the registry or is
non-commercial. `verify` matches quotes ignoring typography (curly quotes, dashes, line breaks)
but not wording, and allows `…` to skip words. CI runs both on every pull request that touches
`content/` (see `.github/workflows/content.yml`).

`export` writes the corpus the AI agent indexes: every card, plus every passage of the
public-domain books, each with its attribution line, so answers can cite the card or the exact
passage. Health web pages aren't in the passage corpus (we don't store their text).
