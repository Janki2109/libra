import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

const _bg = Color(0xFFF0F4FF);
const _bgCard = Color(0xFFFFFFFF);
const _blue = Color(0xFF1565C0);
const _border = Color(0xFFBBDEFB);
const _textPri = Color(0xFF0A1628);
const _textMuted = Color(0xFF546E7A);

class LegalNotesScreen extends StatefulWidget {
  const LegalNotesScreen({super.key});
  @override
  State<LegalNotesScreen> createState() => _LegalNotesScreenState();
}

class _LegalNotesScreenState extends State<LegalNotesScreen> {
  String? _selectedSubject;
  String? _selectedTopic;

  final List<Map<String, dynamic>> _subjects = [
    {
      'name': 'Constitutional Law',
      'icon': '📜',
      'color': const Color(0xFF1565C0),
      'topics': [
        {
          'title': 'Preamble of India',
          'content': '''THE PREAMBLE

"WE, THE PEOPLE OF INDIA, having solemnly resolved to constitute India into a SOVEREIGN SOCIALIST SECULAR DEMOCRATIC REPUBLIC and to secure to all its citizens:
JUSTICE, social, economic and political;
LIBERTY of thought, expression, belief, faith and worship;
EQUALITY of status and of opportunity;
and to promote among them all
FRATERNITY assuring the dignity of the individual and the unity and integrity of the Nation..."

KEY POINTS:
• Added by 42nd Amendment (1976): Socialist, Secular, Integrity
• Sovereign - Free from external control
• Socialist - Social ownership of production
• Secular - No state religion
• Democratic - Elected government
• Republic - Elected head of state

LANDMARK CASE:
Kesavananda Bharati v. State of Kerala (1973) - Preamble is part of Constitution but cannot be used to override fundamental rights.'''
        },
        {
          'title': 'Fundamental Rights (Art 12-35)',
          'content': '''FUNDAMENTAL RIGHTS - PART III

Article 12: Definition of State
Article 13: Laws inconsistent with FRs are void

Article 14: Right to Equality
• Equality before law
• Equal protection of law

Article 15: No discrimination on grounds of religion, race, caste, sex, place of birth
• Art 15(3): Special provisions for women & children
• Art 15(4): Special provisions for backward classes

Article 16: Equality of opportunity in public employment

Article 17: Abolition of Untouchability

Article 18: Abolition of Titles

RIGHT TO FREEDOM (Art 19-22):
Article 19: 6 freedoms
(a) Speech & Expression
(b) Assembly peacefully
(c) Form associations
(d) Move freely
(e) Reside anywhere
(f) Practice profession

Article 21: Right to Life & Personal Liberty
• Most expansive FR
• Includes: right to dignity, livelihood, health, education, privacy

LANDMARK CASES:
• Maneka Gandhi v. UOI (1978) - Art 21 expanded
• K.S. Puttaswamy v. UOI (2017) - Privacy is FR
• Vishaka v. State of Rajasthan (1997) - Sexual harassment guidelines'''
        },
        {
          'title': 'Directive Principles (Art 36-51)',
          'content': '''DIRECTIVE PRINCIPLES OF STATE POLICY - PART IV

Art 36-51 - Non-justiciable but fundamental to governance

SOCIALIST PRINCIPLES:
Art 38 - Minimize inequality
Art 39 - Adequate livelihood, equal pay, no exploitation
Art 41 - Right to work, education & public assistance
Art 42 - Maternity relief
Art 43 - Living wage for workers
Art 45 - Free & compulsory education for children (now FR under Art 21A)

GANDHIAN PRINCIPLES:
Art 40 - Village Panchayats
Art 43 - Cottage industries
Art 46 - Promotion of SC/ST interests
Art 47 - Prohibition of intoxicating drinks
Art 48 - Cow protection

LIBERAL PRINCIPLES:
Art 44 - Uniform Civil Code
Art 45 - Free & compulsory education
Art 51 - International peace & security

KEY DIFFERENCE:
FRs = Justiciable (can approach court)
DPSPs = Non-justiciable (cannot approach court)

But DPSPs can be used to RESTRICT FRs (Art 19)'''
        },
        {
          'title': 'Amendment Procedure - Art 368',
          'content': '''AMENDMENT OF CONSTITUTION - ARTICLE 368

THREE METHODS:

1. SIMPLE MAJORITY (Outside Art 368):
• Adding/removing states
• Citizenship laws
• 5th & 6th Schedules

2. SPECIAL MAJORITY (Art 368):
• 2/3rd majority of members PRESENT & VOTING
• AND majority of TOTAL membership of each House
• Most Constitutional amendments

3. SPECIAL MAJORITY + RATIFICATION:
• Half of state legislatures must also ratify
• Federal matters:
  - Election of President
  - Extent of executive/legislative power
  - Supreme Court & High Courts
  - Distribution of powers (7th Schedule)
  - Representation in Parliament

BASIC STRUCTURE DOCTRINE:
Parliament cannot amend Basic Structure
Kesavananda Bharati (1973) established this
Basic features include: Supremacy of Constitution, Republican form, Separation of powers, Federal character, Judicial review, Fundamental Rights'''
        },
      ]
    },
    {
      'name': 'Indian Penal Code / BNS',
      'icon': '⚖️',
      'color': const Color(0xFFD9534F),
      'topics': [
        {
          'title': 'BNS Overview - Key Sections',
          'content': '''BHARATIYA NYAYA SANHITA (BNS) 2023
Replaced IPC 1860 from July 1, 2024

KEY SECTIONS:

BNS 101 (IPC 299/300) - Culpable Homicide & Murder
• Culpable homicide = causing death with intention
• Murder = most aggravated form
• Punishment: Death or Life imprisonment

BNS 103 (IPC 302) - Punishment for Murder
• Death or imprisonment for life + fine

BNS 111 (IPC 120B) - Criminal Conspiracy
• 6 months to life imprisonment

BNS 115 (IPC 324) - Voluntarily causing hurt
• Imprisonment up to 3 years or fine or both

BNS 127 (IPC 375) - Sexual Assault/Rape
• Minimum 10 years to life
• Death in aggravated cases

BNS 177 (IPC 420) - Cheating
• Imprisonment up to 7 years + fine

BNS 197 (IPC 498A) - Cruelty to Wife
• Imprisonment up to 3 years + fine

BNS 285 (IPC 503) - Criminal Intimidation
• Imprisonment up to 2 years or fine or both

NEW ADDITIONS IN BNS:
• Organized crime (BNS 111)
• Terrorism (BNS 113)
• Petty organized crime (BNS 112)'''
        },
        {
          'title': 'Bail Laws - BNSS',
          'content': '''BAIL PROVISIONS - BNSS 2023
(Replaced CrPC 1973)

TYPES OF BAIL:

1. REGULAR BAIL (Sec 480 BNSS / Sec 437 CrPC)
• After arrest
• Magistrate/Court can grant
• Factors: Nature of crime, antecedents, evidence

2. ANTICIPATORY BAIL (Sec 482 BNSS / Sec 438 CrPC)
• Before arrest
• Sessions Court or High Court
• Fear of arrest for non-bailable offence

3. DEFAULT BAIL (Sec 479 BNSS / Sec 167 CrPC)
• If police fails to file chargesheet in time
• 60 days for offences punishable with death/life
• 90 days for other offences
• Accused gets bail as of right

BAIL CONDITIONS:
• Surety
• Mark presence at police station
• Not to tamper evidence
• Not to contact witnesses

LANDMARK CASES:
• Arnesh Kumar v. State of Bihar - Arrest not automatic
• P. Chidambaram v. CBI - Factors for bail
• Satender Kumar Antil v. CBI - Default bail rights'''
        },
        {
          'title': 'Offences Against Women',
          'content': '''OFFENCES AGAINST WOMEN

RAPE (BNS 64/IPC 375):
• Penetration without consent
• Minimum 10 years, maximum life
• Death in gang rape/repeat offence

DOMESTIC VIOLENCE:
• Protection of Women from DV Act 2005
• Civil remedy + Magistrate orders
• Protection, residence, maintenance, custody orders

DOWRY HARASSMENT (BNS 85/IPC 498A):
• Husband or relatives
• Cruelty to coerce for dowry
• 3 years + fine

DOWRY DEATH (BNS 80/IPC 304B):
• Death within 7 years of marriage
• Presumption of dowry death
• 7 years to life imprisonment

SEXUAL HARASSMENT (BNS 75/IPC 354):
• Criminal force on woman
• 1-5 years imprisonment

STALKING (BNS 78/IPC 354D):
• Repeatedly following/monitoring
• 1st offence: 3 years
• Subsequent: 5 years

POCSO ACT 2012:
• Protection of Children from Sexual Offences
• Child = below 18 years
• Mandatory reporting
• Special courts'''
        },
      ]
    },
    {
      'name': 'Law of Contracts',
      'icon': '🤝',
      'color': const Color(0xFF2E8B57),
      'topics': [
        {
          'title': 'Essential Elements of Contract',
          'content': '''INDIAN CONTRACT ACT 1872

ESSENTIAL ELEMENTS (Section 10):

1. OFFER & ACCEPTANCE
• Offer = Definite proposition
• Acceptance = Unconditional assent
• Counter-offer = rejection of original offer

2. CONSIDERATION (Sec 2(d))
• Something in return
• Past, present or future
• Need not be adequate but must be real
• "Something of value in the eye of law"

3. CAPACITY TO CONTRACT (Sec 11)
• Major (18+ years)
• Of sound mind
• Not disqualified by law

4. FREE CONSENT (Sec 14)
• Not obtained by:
  - Coercion (Sec 15)
  - Undue Influence (Sec 16)
  - Fraud (Sec 17)
  - Misrepresentation (Sec 18)
  - Mistake (Sec 20-22)

5. LAWFUL OBJECT (Sec 23)
• Not forbidden by law
• Not fraudulent
• Not injurious to person/property
• Not immoral or opposed to public policy

6. NOT EXPRESSLY DECLARED VOID (Sec 24-30)
• Agreements in restraint of marriage
• Agreements in restraint of trade
• Wagering agreements

LANDMARK CASE:
Carlill v. Carbolic Smoke Ball Co. - Offer to the world'''
        },
        {
          'title': 'Void & Voidable Contracts',
          'content': '''VOID & VOIDABLE CONTRACTS

VOID CONTRACT (Sec 2(j)):
• No legal effect from beginning (void ab initio)
• OR becomes void later
• Neither party can sue

EXAMPLES OF VOID AGREEMENTS:
• Agreement by minor (but minor can take benefit)
• Agreement without consideration (with exceptions)
• Restraint of marriage (Sec 26)
• Restraint of trade (Sec 27)
• Wagering agreements (Sec 30)
• Uncertain agreements (Sec 29)

VOIDABLE CONTRACT (Sec 2(i)):
• Valid until avoided by aggrieved party
• Can be enforced or avoided at OPTION of aggrieved

WHEN VOIDABLE:
• Coercion (Sec 15)
• Undue Influence (Sec 16)
• Fraud (Sec 17)
• Misrepresentation (Sec 18)

CONSEQUENCES:
Void = No restitution generally
Voidable = Restitution + Compensation possible

BREACH OF CONTRACT:
Actual Breach = Refusal to perform
Anticipatory Breach = Before due date'''
        },
      ]
    },
    {
      'name': 'Law of Evidence',
      'icon': '🔍',
      'color': const Color(0xFF7C3AED),
      'topics': [
        {
          'title': 'Indian Evidence Act - Key Concepts',
          'content': '''BHARATIYA SAKSHYA ADHINIYAM (BSA) 2023
Replaced Indian Evidence Act 1872

KEY CONCEPTS:

FACT (Sec 3):
• Fact in Issue = Fact which party must prove/disprove
• Relevant Fact = Facts making facts in issue probable

EVIDENCE:
• Oral Evidence = What witnesses saw/heard
• Documentary Evidence = Documents produced

BURDEN OF PROOF (Sec 101-103):
• On person who asserts the fact
• Exception: When presumed by law

PRESUMPTIONS:
• May presume (discretionary)
• Shall presume (mandatory)
• Conclusive proof (cannot be rebutted)

CONFESSION (Sec 24-30):
• Only admissible if voluntary
• Before Magistrate (Judicial) = admissible
• Before Police Officer = NOT admissible
• Retracted confession needs corroboration

DYING DECLARATION:
• Statement by dying person
• Reason: "nemo moriturus praesumitur mentire"
• Need not be corroborated
• Multiple dying declarations - consistent one prevails

HEARSAY:
• Generally not admissible
• Exceptions: Dying declaration, res gestae

EXPERT EVIDENCE:
• Doctor, Handwriting expert, etc.
• Opinion evidence - court not bound'''
        },
      ]
    },
    {
      'name': 'Family Law',
      'icon': '👨‍👩‍👧',
      'color': const Color(0xFFD4A017),
      'topics': [
        {
          'title': 'Hindu Marriage Act 1955',
          'content': '''HINDU MARRIAGE ACT 1955

APPLICABILITY:
• Hindus, Buddhists, Jains, Sikhs
• Any person who is NOT Muslim, Christian, Parsi, Jew

CONDITIONS FOR VALID MARRIAGE (Sec 5):
1. Neither party has living spouse
2. Neither party is unsound mind
3. Male = 21 years, Female = 18 years
4. Not within prohibited degrees of relationship
5. Not sapindas (blood relatives)

VOID MARRIAGE (Sec 11):
• Bigamy
• Prohibited degrees
• Sapinda relationship

VOIDABLE MARRIAGE (Sec 12):
• Impotence
• Unsoundness of mind
• Fraud, force or concealment
• Pre-marriage pregnancy by another

GROUNDS FOR DIVORCE (Sec 13):
• Adultery
• Cruelty (physical or mental)
• Desertion (2 years)
• Conversion to another religion
• Mental disorder
• Leprosy/Venereal disease
• Renounced world
• Not heard of for 7 years

MUTUAL CONSENT (Sec 13B):
• Separation for 1 year
• Both parties agree

MAINTENANCE (Sec 24):
• Pendente lite maintenance
• Permanent alimony (Sec 25)

LANDMARK CASE:
Naveen Kohli v. Naveen Kohli - Irretrievable breakdown'''
        },
        {
          'title': 'Muslim Personal Law',
          'content': '''MUSLIM PERSONAL LAW

MARRIAGE (NIKAH):
• Contract between parties
• Offer (Ijab) + Acceptance (Qabul)
• Witnesses required (2 males or 1 male + 2 females)
• Mahr (dower) is essential

TYPES:
• Sahih (Valid) - All conditions fulfilled
• Fasid (Irregular) - Can be regularized
• Batil (Void) - Cannot be regularized

DIVORCE:
1. TALAQ by Husband:
• Talaq-ul-Sunnat (Ahsan/Hasan) - Revocable
• Triple Talaq (Talaq-ul-Biddat) - NOW ILLEGAL
  Muslim Women Protection Act 2019

2. KHUL (By Wife):
• Return of dower to husband

3. MUBARAT (Mutual):
• Both parties agree

4. JUDICIAL DIVORCE:
• Dissolution of Muslim Marriage Act 1939
• Grounds: Missing, prison, failure to maintain, cruelty etc.

MAINTENANCE:
• During iddat period (3 months)
• Shah Bano Case (1985) - Sec 125 CrPC applicable
• Muslim Women Act 1986 - Reversal
• Daniel Latifi Case (2001) - Reasonable provision

INHERITANCE (MIRATH):
• Male gets double share of female
• Spouse, children, parents are Class I heirs'''
        },
      ]
    },
    {
      'name': 'Company Law',
      'icon': '🏢',
      'color': const Color(0xFF0288D1),
      'topics': [
        {
          'title': 'Companies Act 2013 - Basics',
          'content': '''COMPANIES ACT 2013

TYPES OF COMPANIES:

1. PRIVATE COMPANY (Sec 2(68)):
• Min 2, Max 200 members
• Restricts share transfer
• Cannot invite public for subscription
• Minimum paid-up capital: ₹1 lakh

2. PUBLIC COMPANY (Sec 2(71)):
• Min 7 members, no maximum
• Shares freely transferable
• Can invite public
• Min capital: ₹5 lakhs

3. ONE PERSON COMPANY (OPC):
• Only 1 member
• Must nominate a person
• Exempt from many compliances

INCORPORATION (Sec 3-22):
• MOA = Memorandum of Association
• AOA = Articles of Association
• Certificate of Incorporation from ROC

DIRECTORS:
• Minimum: Private = 2, Public = 3
• Maximum: 15 (can increase by special resolution)
• DIN = Director Identification Number
• Independent Directors required in listed companies

MEETINGS:
• AGM = Annual General Meeting (once a year)
• EGM = Extraordinary General Meeting
• Board Meeting = Every quarter

WINDING UP (Sec 270):
• Voluntary (members or creditors)
• By Tribunal
• Compulsory liquidation'''
        },
      ]
    },
    {
      'name': 'Law of Torts',
      'icon': '🏛️',
      'color': const Color(0xFF00897B),
      'topics': [
        {
          'title': 'Introduction to Torts',
          'content': '''LAW OF TORTS

DEFINITION:
• Civil wrong (not crime)
• Gives rise to civil liability
• Remedy = Damages

ESSENTIALS:
1. Wrongful act or omission
2. Legal damage (injuria = violation of legal right)
3. Legal remedy (damages)

MAXIMS:
• Damnum sine injuria = Damage without legal injury (NO remedy)
• Injuria sine damnum = Legal injury without damage (remedy available)

GENERAL DEFENCES:
• Volenti non fit injuria (Consent)
• Plaintiff's own fault
• Act of God (Vis Major)
• Inevitable accident
• Private defence
• Statutory authority
• Necessity

VICARIOUS LIABILITY:
• Employer liable for employee's torts
• During course of employment
• Principle-Agent relationship

STRICT LIABILITY (Rylands v. Fletcher):
• Escape of dangerous thing
• No need to prove negligence

ABSOLUTE LIABILITY (M.C. Mehta v. UOI):
• No exceptions
• Enterprise engaged in hazardous activity

NEGLIGENCE:
• Duty of care
• Breach of duty
• Damage caused by breach

DEFAMATION:
• Libel (written) = actionable per se
• Slander (spoken) = need proof of damage'''
        },
      ]
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: Column(children: [
        // Header
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
                colors: [Color(0xFF0A1628), Color(0xFF1565C0)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight),
          ),
          child: SafeArea(
              bottom: false,
              child: Column(children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 4, 16, 12),
                  child: Row(children: [
                    IconButton(
                        icon: const Icon(Icons.arrow_back_rounded,
                            color: Colors.white),
                        onPressed: _selectedSubject != null
                            ? () => setState(() {
                                  _selectedSubject = null;
                                  _selectedTopic = null;
                                })
                            : () => context.pop()),
                    Expanded(
                        child: Text(
                            _selectedTopic != null
                                ? _selectedTopic!
                                : _selectedSubject != null
                                    ? _selectedSubject!
                                    : 'Legal Notes',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w700),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis)),
                    if (_selectedSubject != null)
                      IconButton(
                          icon: const Icon(Icons.home_rounded,
                              color: Colors.white),
                          onPressed: () => setState(() {
                                _selectedSubject = null;
                                _selectedTopic = null;
                              })),
                  ]),
                ),
              ])),
        ),

        Expanded(
            child: _selectedTopic != null
                ? _buildContent()
                : _selectedSubject != null
                    ? _buildTopics()
                    : _buildSubjects()),
      ]),
    );
  }

  // ── Subjects Grid ──────────────────────────────────
  Widget _buildSubjects() => LayoutBuilder(
      builder: (context, constraints) {
        // 2 columns on typical mobile widths; falls back to 1 on very
        // narrow screens so long subject names never get squeezed.
        final crossAxisCount = constraints.maxWidth < 320 ? 1 : 2;
        return ListView(
          padding: EdgeInsets.fromLTRB(
              16, 16, 16, 16 + MediaQuery.of(context).padding.bottom),
          children: [
            // Hero
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                  color: _bgCard,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: _border),
                  boxShadow: [
                    BoxShadow(
                        color: _blue.withValues(alpha: 0.06),
                        blurRadius: 10,
                        offset: const Offset(0, 3))
                  ]),
              child: Row(children: [
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                      Text('Legal Notes',
                          style: TextStyle(
                              color: _textPri,
                              fontSize: 20,
                              fontWeight: FontWeight.w800)),
                      SizedBox(height: 4),
                      Text('Tap a subject to start studying',
                          style: TextStyle(color: _textMuted, fontSize: 12)),
                    ])),
                const SizedBox(width: 10),
                Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                        color: _blue.withValues(alpha: 0.1),
                        shape: BoxShape.circle),
                    child: const Icon(Icons.menu_book_rounded,
                        color: _blue, size: 24)),
              ]),
            ),
            const SizedBox(height: 16),

            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  // A fixed pixel extent (not an aspect ratio) sized to
                  // comfortably fit a 2-line subject name — the previous
                  // childAspectRatio: 1.3 gave every card a height too
                  // short for names like "Indian Penal Code / BNS" once
                  // they wrapped, which is what caused the bottom overflow.
                  mainAxisExtent: 148),
              itemCount: _subjects.length,
              itemBuilder: (_, i) {
                final s = _subjects[i];
                final color = s['color'] as Color;
                return GestureDetector(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    setState(() => _selectedSubject = s['name']);
                  },
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                        color: _bgCard,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: _border),
                        boxShadow: [
                          BoxShadow(
                              color: _blue.withValues(alpha: 0.06),
                              blurRadius: 8,
                              offset: const Offset(0, 2))
                        ]),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(children: [
                            Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                    color: color.withValues(alpha: 0.1),
                                    shape: BoxShape.circle),
                                child: Center(
                                    child: Text(s['icon'],
                                        style:
                                            const TextStyle(fontSize: 18)))),
                            const Spacer(),
                            Icon(Icons.chevron_right_rounded,
                                color: color.withValues(alpha: 0.5), size: 20),
                          ]),
                          const SizedBox(height: 8),
                          Flexible(
                            child: Text(s['name'],
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    color: _textPri,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                    height: 1.2)),
                          ),
                          const SizedBox(height: 4),
                          Text('${(s['topics'] as List).length} topics',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: color,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600)),
                        ]),
                  ),
                );
              },
            ),
          ],
        );
      });

  // ── Topics List ────────────────────────────────────
  Widget _buildTopics() {
    final subject = _subjects.firstWhere((s) => s['name'] == _selectedSubject);
    final topics = subject['topics'] as List;
    final color = subject['color'] as Color;
    return ListView.builder(
      padding: EdgeInsets.fromLTRB(
          16, 16, 16, 16 + MediaQuery.of(context).padding.bottom),
      itemCount: topics.length,
      itemBuilder: (_, i) {
        final t = topics[i] as Map<String, dynamic>;
        return GestureDetector(
          onTap: () {
            HapticFeedback.lightImpact();
            setState(() => _selectedTopic = t['title']);
          },
          child: Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
                color: _bgCard,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: color.withValues(alpha: 0.2)),
                boxShadow: [
                  BoxShadow(
                      color: _blue.withValues(alpha: 0.05),
                      blurRadius: 6,
                      offset: const Offset(0, 2))
                ]),
            child: Row(children: [
              Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10)),
                  child: Center(
                      child: Text('${i + 1}',
                          style: TextStyle(
                              color: color,
                              fontWeight: FontWeight.w800,
                              fontSize: 18)))),
              const SizedBox(width: 14),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                    Text(t['title'],
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: _textPri,
                            fontWeight: FontWeight.w700,
                            fontSize: 14)),
                    const SizedBox(height: 3),
                    Text('Tap to read notes',
                        style:
                            const TextStyle(color: _textMuted, fontSize: 11)),
                  ])),
              const SizedBox(width: 8),
              Icon(Icons.arrow_forward_ios_rounded,
                  color: color.withValues(alpha: 0.5), size: 14),
            ]),
          ),
        );
      },
    );
  }

  // ── Content View ───────────────────────────────────
  Widget _buildContent() {
    final subject = _subjects.firstWhere((s) => s['name'] == _selectedSubject);
    final topics = subject['topics'] as List;
    final topic = topics.firstWhere((t) => t['title'] == _selectedTopic);
    final color = subject['color'] as Color;
    final content = topic['content'] as String;

    return Column(children: [
      // Topic header
      Container(
        color: color.withValues(alpha: 0.06),
        padding: const EdgeInsets.all(16),
        child: Row(children: [
          Text(subject['icon'], style: const TextStyle(fontSize: 24)),
          const SizedBox(width: 10),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                Text(topic['title'],
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w800,
                        fontSize: 15)),
                Text(subject['name'],
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: _textMuted, fontSize: 11)),
              ])),
          GestureDetector(
            onTap: () {
              HapticFeedback.lightImpact();
              Clipboard.setData(ClipboardData(text: content));
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('Notes copied!'),
                  backgroundColor: Color(0xFF1565C0),
                  behavior: SnackBarBehavior.floating));
            },
            child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8)),
                child: Icon(Icons.copy_rounded, color: color, size: 18)),
          ),
        ]),
      ),

      // Notes content
      Expanded(
          child: ListView(
              padding: EdgeInsets.fromLTRB(
                  16, 16, 16, 16 + MediaQuery.of(context).padding.bottom),
              children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
              color: _bgCard,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _border, width: 0.8),
              boxShadow: [
                BoxShadow(
                    color: _blue.withValues(alpha: 0.05),
                    blurRadius: 8,
                    offset: const Offset(0, 2))
              ]),
          child: SelectableText(content,
              style: const TextStyle(
                  color: _textPri,
                  fontSize: 14,
                  height: 1.7,
                  fontFamily: 'monospace')),
        ),
        const SizedBox(height: 20),
        // Navigation buttons
        Row(children: [
          if (topics.indexOf(
                  topics.firstWhere((t) => t['title'] == _selectedTopic)) >
              0)
            Expanded(
                child: OutlinedButton.icon(
              onPressed: () {
                final idx = topics.indexOf(
                    topics.firstWhere((t) => t['title'] == _selectedTopic));
                setState(() => _selectedTopic = topics[idx - 1]['title']);
              },
              icon: const Icon(Icons.arrow_back_rounded, size: 16),
              label: const Text('Previous'),
              style: OutlinedButton.styleFrom(
                  foregroundColor: _blue, side: BorderSide(color: _border)),
            )),
          const SizedBox(width: 10),
          if (topics.indexOf(
                  topics.firstWhere((t) => t['title'] == _selectedTopic)) <
              topics.length - 1)
            Expanded(
                child: ElevatedButton.icon(
              onPressed: () {
                final idx = topics.indexOf(
                    topics.firstWhere((t) => t['title'] == _selectedTopic));
                setState(() => _selectedTopic = topics[idx + 1]['title']);
              },
              icon: const Icon(Icons.arrow_forward_rounded,
                  color: Colors.white, size: 16),
              label: const Text('Next Topic',
                  style: TextStyle(color: Colors.white)),
              style: ElevatedButton.styleFrom(backgroundColor: _blue),
            )),
        ]),
        const SizedBox(height: 40),
      ])),
    ]);
  }
}
