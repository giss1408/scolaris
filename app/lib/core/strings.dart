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
