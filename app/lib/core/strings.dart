/// Every visible text, in French (the only market). One file keeps wording consistent and ready to move to ARB files if a second language comes.
abstract final class S {
  static const appName = 'Scolaris';
  static const retry = 'Réessayer';
  static const cancel = 'Annuler';
  static const confirm = 'Confirmer';
  static const save = 'Enregistrer';
  static const next = 'Suivant';
  static const back = 'Retour';
  static const finish = 'Terminer';
  static const search = 'Rechercher';
  static const required = 'Champ obligatoire';

  // Sign-in
  static const signIn = 'Se connecter';
  static const phone = 'Numéro de téléphone';
  static const phoneHelp = 'Ex. 07 01 02 03 04';
  static const password = 'Mot de passe';
  static const activateTitle = 'Activer mon compte';
  static const activateHelp = 'Entrez le code reçu par WhatsApp et choisissez votre mot de passe.';
  static const activationCode = 'Code reçu (6 chiffres)';
  static const newPassword = 'Nouveau mot de passe';
  static const haveCode = "J'ai reçu un code d'activation";
  static const backToSignIn = 'Retour à la connexion';
  static const activate = 'Activer';

  // Navigation
  static const tabHome = 'Accueil';
  static const tabStudents = 'Élèves';
  static const tabArrears = 'Impayés';
  static const tabProfile = 'Profil';
  static const tabGrades = 'Notes';

  // Home
  static String hello(String name) => 'Bonjour $name';
  static const collectedToday = "Encaissé aujourd'hui";
  static const collectedMonth = 'Encaissé ce mois';
  static const remaining = 'Reste à payer';
  static const overdue = 'En retard';
  static const recovery = 'Taux de recouvrement';
  static const pay = 'Encaisser';
  static const newStudent = 'Nouvel élève';
  static const toHandle = 'À traiter';
  static const seeAll = 'Voir tout';

  // Students
  static const noStudents = 'Aucun élève pour le moment.';
  static const noResult = 'Aucun résultat.';
  static const searchStudent = 'Nom, prénom ou matricule';
  static const studentSheet = "Fiche de l'élève";
  static const contacts = 'Contacts';
  static const family = 'Famille';
  static const account = 'Situation financière';
  static const history = 'Historique des paiements';
  static const call = 'Appeler';
  static const whatsapp = 'WhatsApp';
  static const assigned = 'Affecté';
  static const notAssigned = 'Non affecté';

  // Payments
  static const amount = 'Montant (FCFA)';
  static const method = 'Moyen de paiement';
  static const reference = "Référence de l'opérateur";
  static const referenceHelp = 'Numéro de transaction ou de chèque';
  static const paymentDone = 'Paiement enregistré';
  static const share = 'Partager';
  static const cancelPayment = 'Annuler ce paiement';
  static const cancelReason = "Motif de l'annulation";
  static const cancelledBadge = 'Annulé';
  static const grantDiscount = 'Accorder une réduction';
  static const discountReason = 'Motif';
  static const paid = 'Payé';
  static const late = 'En retard';
  static const toPay = 'À payer';
  static const total = 'Total dû';
  static const received = 'Déjà réglé';
  static const rePassword = 'Pour votre sécurité, confirmez votre mot de passe.';

  // Arrears
  static const noArrears = 'Aucun impayé. Bravo !';
  static String lateDays(int d) => d <= 1 ? 'Retard de $d jour' : 'Retard de $d jours';
  static String children(int n) => n <= 1 ? '1 enfant' : '$n enfants';

  // Student form
  static const stepIdentity = 'Identité';
  static const stepParent = 'Parent';
  static const stepClass = 'Classe';
  static String step(int i, int n) => 'Étape $i sur $n';
  static const lastName = 'Nom';
  static const firstNames = 'Prénoms';
  static const sex = 'Sexe';
  static const male = 'Garçon';
  static const female = 'Fille';
  static const birthDate = 'Date de naissance';
  static const birthPlace = 'Lieu de naissance';
  static const matricule = 'Matricule national (MENA)';
  static const matriculeHelp = 'Facultatif, unique pour chaque élève';
  static const assignedByState = "Élève affecté par l'État";
  static const parentName = 'Nom du parent ou tuteur';
  static const relation = 'Lien';
  static const optin = "Le parent accepte de recevoir les messages de l'école sur WhatsApp";
  static const financialResp = 'Responsable des paiements';
  static const classroom = 'Classe';
  static const options = 'Services choisis';
  static const summary = 'Récapitulatif';
  static const createStudent = "Inscrire l'élève";

  // Profile
  static const account_ = 'Compte';
  static const school = 'Établissement';
  static const application = 'Application';
  static const changePassword = 'Changer mon mot de passe';
  static const team = 'Équipe';
  static const fees = 'Frais de scolarité';
  static const classes = 'Classes';
  static const signOut = 'Se déconnecter';
  static const signOutAsk = 'Se déconnecter de Scolaris ?';
  static const currentPassword = 'Mot de passe actuel';
  static const passwordChanged = 'Mot de passe modifié';
  static const addMember = 'Ajouter un membre';
  static const memberName = 'Nom complet';
  static const memberRole = 'Fonction';
  static const memberHelp = "Le compte sera activé avec un code envoyé par WhatsApp par l'équipe Scolaris.";
  static const memberAdded = 'Membre ajouté. Un code WhatsApp lui sera envoyé.';
  static const remove = 'Retirer';
  static const forbidden = "Cette action n'est pas disponible pour votre fonction.";
  static const addLine = 'Ajouter une ligne';
  static const label = 'Libellé';
  static const dueDate = 'Date limite';
  static const optional = 'Facultatif';
  static const className = 'Nom de la classe';
  static const level = 'Niveau';
  static const addClass = 'Ajouter une classe';

  // Grades
  static const gradesTitle = 'Notes et bulletins';
  static const pickClass = 'Choisissez une classe';
  static const evaluations = 'Évaluations';
  static const results = 'Résultats';
  static const roll = 'Appel';
  static const newEvaluation = 'Nouvelle évaluation';
  static const subject = 'Matière';
  static const period = 'Trimestre';
  static const kind = 'Type';
  static const outOf = 'Notée sur';
  static const enterGrades = 'Saisir les notes';
  static const absentLabel = 'Absent';
  static const lockEval = 'Valider (verrouiller)';
  static const unlockEval = 'Déverrouiller';
  static const lockedBadge = 'Validée';
  static const average = 'Moyenne';
  static const rank = 'Rang';
  static const reportCard = 'Bulletin';
  static const conduct = 'Conduite (/20)';
  static const appreciation = 'Appréciation';
  static const decision = 'Décision du conseil';
  static const sanction = 'Sanction';
  static const yearAverage = 'Année';
  static const subjectsTitle = 'Matières et coefficients';
  static const addSubject = 'Ajouter une matière';
  static const noEvaluations = "Aucune évaluation pour ce trimestre.";
  static const noSubjects = "Ajoutez d'abord les matières (Profil > Matières et coefficients).";
  static const markPresent = 'Présent';
  static const late_ = 'Retard';
  static const saveRoll = "Enregistrer l'appel";
  static String periodLabel(int p) => p == 0 ? 'Année' : (p == 1 ? '1er trimestre' : '$p\u1d49 trimestre');
  static String kindEval(String k) => switch (k) { 'devoir' => 'Devoir', 'interrogation' => 'Interrogation', 'composition' => 'Composition', _ => k };
  static String honourLabel(String h) => switch (h) { 'felicitations' => 'Félicitations', 'encouragements' => 'Encouragements', 'tableau_honneur' => "Tableau d'honneur", _ => h };

  // Timetable
  static const tabSchedule = 'Horaires';
  static const timetable = 'Emploi du temps';
  static const myTimetable = 'Mon emploi du temps';
  static const addSlot = 'Ajouter un cours';
  static const noClassToday = "Pas de cours ce jour.";
  static const nowBadge = 'En cours';
  static const nextBadge = 'Prochain';
  static const noTeacher = 'Sans enseignant';
  static const room = 'Salle';
  static const startTime = 'Début';
  static const endTime = 'Fin';
  static const day = 'Jour';
  static const noWeek = "Aucun cours n'est encore planifié.";
  static const slotAdded = 'Cours ajouté';
  static const removeSlotAsk = 'Supprimer ce cours ?';
  static const days = ['Lundi', 'Mardi', 'Mercredi', 'Jeudi', 'Vendredi', 'Samedi'];
  static const daysShort = ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam'];

  /// Name of any weekday, 1 = Monday ... 7 = Sunday (the timetable only has Monday-Saturday, a calendar date can be a Sunday).
  static String dayLong(int weekday) => const ['Lundi', 'Mardi', 'Mercredi', 'Jeudi', 'Vendredi', 'Samedi', 'Dimanche'][(weekday - 1) % 7];

  // Roll call of a course, parent reports, substitutes
  static const doRoll = "Faire l'appel";
  static const courseRoll = "Appel du cours";
  static const rollSaved = 'Appel enregistré';
  static String parentsTold(int n) => n == 0 ? 'Aucun parent à prévenir.' : (n == 1 ? '1 parent prévenu.' : '$n parents prévenus.');
  static const present = 'Présent';
  static const reportedByParent = 'Signalée par les parents';
  static const absentAllDay = 'Absent toute la journée';
  static const substituteTitle = 'Remplaçant';
  static const substituteHelp = 'Facultatif : les familles sont prévenues du nom du remplaçant.';
  static const chooseSubstitute = 'Choisir un remplaçant';
  static const changeSubstitute = 'Changer le remplaçant';
  static const noSubstitute = 'Pas de remplaçant';
  static const substituteSaved = 'Remplaçant enregistré.';
  static String replacedBy(String n) => 'Remplacé par $n';
  static const replacement = 'Remplacement';
  static const reportAbsence = 'Signaler une absence';
  static const reportedAbsences = 'Absences signalées';
  static const reportDay = 'Jour';
  static const reportSent = "L'école est prévenue.";
  static const withdraw = 'Retirer';
  static const reportHelp = "L'école verra votre message à l'appel. C'est elle qui décide de justifier l'absence.";
  static String reportReason(String r) => switch (r) { 'maladie' => 'Maladie', 'rendez_vous' => 'Rendez-vous', 'famille' => 'Raison familiale', 'autre' => 'Autre', _ => r };
  static const atCourse = 'Pendant le cours';

  // Logo, messages, subscription
  static const schoolLogo = "Logo de l'école";
  static const pickLogo = 'Choisir une image';
  static const removeLogo = 'Retirer le logo';
  static const logoHelp = "PNG ou JPEG, 512 Ko au maximum. Il s'affiche dans l'application, sur les reçus et sur les bulletins.";
  static const logoSaved = 'Logo enregistré.';
  static const autoWhatsapp = 'Envoi automatique par Scolaris (avancé)';
  static const autoWhatsappHelp = "Facultatif : Scolaris envoie lui-même les messages, depuis son numéro WhatsApp Business, sans que la secrétaire intervienne. Par défaut, c'est la secrétaire qui les transmet depuis le numéro de l'école.";
  static const schoolWhatsapp = "Numéro WhatsApp de l'école";
  static const schoolWhatsappHelp = "Les messages aux familles (absences, cours annulés, remplaçants, relances) sont rédigés par l'application ; la secrétaire les transmet depuis ce numéro, et les réponses des parents arrivent sur ce numéro, dans le WhatsApp de l'école.";
  static const noWhatsappNumber = 'Aucun';
  static const whatsappNumberSaved = 'Numéro enregistré.';
  static const removeNumber = 'Retirer le numéro';
  static const toSendTab = 'À envoyer';
  static const historyTab = 'Historique';
  static const sendFromSchool = "Envoyez depuis le numéro WhatsApp de l'école :";
  static const repliesHere = 'Les réponses des parents arrivent sur ce numéro, dans votre WhatsApp.';
  static const nothingToSend = 'Aucun message à envoyer.';
  static const noNumberYet = "Aucun message n'est préparé tant que le directeur n'a pas enregistré le numéro WhatsApp de l'école (Profil).";
  static const outsideSendHours = "Il est tard ou c'est dimanche : mieux vaut envoyer ce message demain matin (7 h - 20 h).";
  static String toSendCount(int n) => n == 1 ? '1 à envoyer' : '$n à envoyer';
  static const withdrawOptin = "Retirer l'accord WhatsApp";
  static const restoreOptin = "Rétablir l'accord WhatsApp";
  static const withdrawOptinAsk = "Plus aucun message WhatsApp ne sera préparé pour ce parent. Ceux qui attendent sont annulés.";
  static const optinWithdrawn = 'Accord retiré : plus de messages pour ce parent.';
  static const optinRestored = 'Accord rétabli.';
  static const messagesLog = 'Messages aux familles';
  static const messagesEmpty = 'Aucun message pour le moment.';
  static const toCall = 'À appeler';
  static const subscription = 'Abonnement Scolaris';
  static const subscriptionTitle = 'Abonnement';
  static const markRead = "J'ai lu";
  static const accessSuspended = 'Accès suspendu';
  static const accessSuspendedText = "L'accès de votre établissement à Scolaris est suspendu. Réglez la mensualité en retard pour le rétablir.";
  static const serviceSuspended = 'Service suspendu pour cet établissement';
  static const contactSchool = "Contactez l'école.";
  static String statusLabel(String s) => switch (s) { 'queued' => 'En attente', 'sent' => 'Envoyé', 'delivered' => 'Reçu', 'read' => 'Lu', 'failed' => 'Échec', 'skipped' => "Pas d'accord WhatsApp", _ => s };
  static String kindMsg(String k) => switch (k) { 'absence' => 'Absence', 'cancellation' => 'Cours annulé', 'substitute' => 'Remplaçant', 'reminder' => 'Relance', _ => 'Message' };

  // How to pay the subscription
  static const howToPay = 'Comment payer';
  static const payTo = 'Envoyez le montant à ce numéro';
  static const payReference = 'Référence à indiquer';
  static const copyNumber = 'Copier le numéro';
  static const numberCopied = 'Numéro copié.';
  static const payHolderHelp = "Le nom affiché par l'opérateur doit être :";
  static const noPaymentNumber = "Le numéro de paiement n'est pas encore communiqué. Contactez l'équipe Scolaris.";
  static const paymentNumbers = 'Paiement des abonnements';
  static const paymentNumbersHelp = "Les numéros Mobile Money où les écoles paient leur abonnement : tous les directeurs et secrétaires les voient. Le changement demande votre mot de passe et votre code d'authentification.";
  static const defaultPrice = 'Prix mensuel par défaut (FCFA)';
  static const defaultPriceHelp = "Proposé à la création d'un abonnement ; vous pouvez fixer un autre prix pour une école.";
  static const paymentNote = 'Message pour les écoles (facultatif)';
  static const addNumber = 'Ajouter un numéro';
  static const holderName = 'Nom du titulaire';
  static const operatorLabel = 'Opérateur';
  static const paymentNumbersSaved = 'Numéros enregistrés.';
  static const emptyMeansDefault = 'Vide : prix par défaut';

  // Scolaris team (platform admin)
  static const imTeam = 'Équipe Scolaris';
  static const totpCode = "Code d'authentification";
  static const schools = 'Écoles';
  static const lateOnes = 'En retard';
  static const setSubscription = "Définir l'abonnement";
  static const monthlyAmount = 'Mensualité (FCFA)';
  static const billingDay = 'Jour de paiement (1 à 28)';
  static const startedOn = 'Début';
  static const graceDays = 'Délai de grâce (jours)';
  static const recordPayment = 'Enregistrer un paiement';
  static const sendReminder = 'Envoyer un rappel';
  static const sendFinal = 'Dernier avis';
  static const blockSchool = "Bloquer l'école";
  static const unblockSchool = "Rétablir l'accès";
  static const blockReason = 'Motif du blocage';
  static const blockOn = 'Suspension annoncée le';
  static const noSubscriptionYet = "Pas d'abonnement défini : cette école n'est jamais en retard.";
  static const noticesHistory = 'Avis envoyés';
  static String seenBy(int a, int b) => 'Vu par $a sur $b';
  static String overdueMonths(int n) => n == 1 ? '1 mensualité en retard' : '$n mensualités en retard';
  static String noticeKind(String k) => switch (k) { 'reminder' => 'Rappel', 'final_notice' => 'Dernier avis', 'blocked' => 'Blocage', 'unblocked' => 'Rétablissement', _ => 'Information' };
  static const confirmBlock = "Les enseignants, le personnel et les parents de cette école n'auront plus accès à Scolaris. La direction et la secrétaire verront la raison et pourront régulariser.";

  // Cancelling a session
  static const cancelCourse = 'Annuler ce cours';
  static const restoreCourse = 'Rétablir';
  static const courseCancelled = 'Cours annulé';
  static const thisWeek = 'Cette semaine';
  static const nextWeek = 'Semaine prochaine';
  static const reasonTitle = 'Motif';
  static const reasonNote = 'Précisions';
  static const reasonNoteRequired = 'Précisez le motif';
  static const cancelInfo = "L'administration est prévenue et les familles voient « cours annulé », sans le motif.";
  static const cancelDone = "Cours annulé. L'administration est prévenue.";
  static const restoreDone = 'Cours rétabli.';
  static const cancelledCourses = 'Cours annulés';
  static const noCancelled = 'Aucun cours annulé à venir.';
  static const copyMessage = 'Copier le message aux familles';
  static const messageCopied = 'Message copié : envoyez-le aux familles.';
  static const restoreAsk = 'Rétablir ce cours ?';
  static String reasonLabel(String r) => switch (r) { 'maladie' => 'Maladie', 'absence_autorisee' => 'Absence autorisée', 'formation' => 'Formation', 'autre' => 'Autre', _ => r };

  // Teacher assignments
  static const noClassAssigned = "Aucune classe ne vous est attribuée pour le moment. Demandez au directeur de vous affecter à vos classes.";
  static const headTeacher = 'Professeur principal';
  static const classTeachers = 'Enseignants de la classe';
  static const assignTeacher = 'Affecter un enseignant';
  static const allSubjects = 'Toutes les matières';
  static const noTeachers = "Aucun enseignant dans l'équipe. Ajoutez-en depuis Profil > Équipe.";
  static const noAssignments = "Personne n'est encore affecté à cette classe.";
  static const noSubjectForYou = "Aucune matière ne vous est attribuée dans cette classe.";
  static const assignmentsSaved = 'Affectations enregistrées';

  // Reminders
  static const reminders = 'Relances';
  static const noReminders = "Aucune relance à envoyer aujourd'hui.";
  static const sendWhatsapp = 'Envoyer sur WhatsApp';
  static const markSent = 'Marquer comme envoyé';
  static const skip = 'Passer';
  static const promise = 'Promesse de paiement';
  static const outsideHours = "Hors des heures d'envoi (7 h - 20 h) ou dimanche : mieux vaut attendre.";
  static const sentAsk = 'Le message a-t-il été envoyé ?';
  static String stepLabel(String s) => switch (s) { 'before' => 'Rappel avant échéance', 'late_3' => 'Premier retard', 'late_10' => 'Second rappel', 'late_20' => 'Invitation à l\'économat', 'escalate' => 'À la direction', _ => s };

  // Parent space
  static const imParent = 'Je suis parent';
  static const imStaff = "Je travaille à l'école";
  static const createAccount = 'Créer mon compte';
  static const yourName = 'Votre nom';
  static const registered = 'Compte créé. Un code vous sera envoyé sur WhatsApp : saisissez-le ici pour activer votre compte.';
  static const myChildren = 'Mes enfants';
  static const noChildren = "Aucun enfant n'est rattaché à votre numéro. Vérifiez auprès de l'école que votre numéro est bien enregistré.";
  static const payAtSchool = "Pour payer : au guichet de l'école, par Wave ou Mobile Money. L'école vous remet un reçu.";
  static const payments = 'Paiements et reçus';
  static const absences = 'Absences et retards';
  static const nothingYet = 'Rien pour le moment.';
  static const headcount = 'Effectifs (DRENA)';
  static const examCandidates = 'Candidats aux examens';
  static const exportCopied = 'Export copié : collez-le dans Excel ou envoyez-le.';
  static const exports = 'Exports';

  static String role(String r) => switch (r) {
        'director' => 'Directeur / Directrice',
        'accountant' => 'Comptable / Caissier',
        'secretary' => 'Secrétaire',
        'teacher' => 'Enseignant(e)',
        'parent' => 'Parent',
        _ => r,
      };
  static String methodLabel(String m) => switch (m) {
        'especes' => 'Espèces',
        'wave' => 'Wave',
        'orange_money' => 'Orange Money',
        'mtn_momo' => 'MTN MoMo',
        'moov_money' => 'Moov Money',
        'virement' => 'Virement',
        'cheque' => 'Chèque',
        _ => m,
      };
  static String kindLabel(String k) => switch (k) {
        'inscription' => 'Inscription',
        'scolarite' => 'Scolarité',
        'cantine' => 'Cantine',
        'transport' => 'Transport',
        'tenue' => 'Tenue',
        'fournitures' => 'Fournitures',
        'assurance' => 'Assurance',
        'coges' => 'COGES',
        'examen' => 'Frais d\'examen',
        'parascolaire' => 'Parascolaire',
        _ => k,
      };
  static String relationLabel(String r) => switch (r) { 'pere' => 'Père', 'mere' => 'Mère', 'tuteur' => 'Tuteur', _ => 'Autre' };
}
