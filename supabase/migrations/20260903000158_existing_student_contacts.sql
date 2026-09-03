-- Completa telefonos de contacto para los alumnos de prueba existentes.

with contact_data(enrollment, tutor_name, phone) as (values
  ('CEI-0301','Laura Pech','999 214 8801'),
  ('CEI-0302','Daniel Torres','999 318 5520'),
  ('CEI-0303','Monica Diaz','999 102 7743'),
  ('CEI-0304','Carlos Lopez','999 410 0304'),
  ('CEI-0305','Maria Chan','999 410 0305'),
  ('CEI-0306','Arturo Solis','999 410 0306'),
  ('CEI-0307','Rebeca Ku','999 410 0307'),
  ('CEI-0308','Ivan Pool','999 410 0308'),
  ('CEI-0309','Paola Canto','999 410 0309'),
  ('CEI-0310','Fernando Ek','999 410 0310')
)
update public.student_contacts contact
set full_name = data.tutor_name, phone = data.phone
from contact_data data
join public.students student on student.enrollment = data.enrollment
where contact.student_id = student.id and contact.primary_contact;

with contact_data(enrollment, tutor_name, phone) as (values
  ('CEI-0301','Laura Pech','999 214 8801'),
  ('CEI-0302','Daniel Torres','999 318 5520'),
  ('CEI-0303','Monica Diaz','999 102 7743'),
  ('CEI-0304','Carlos Lopez','999 410 0304'),
  ('CEI-0305','Maria Chan','999 410 0305'),
  ('CEI-0306','Arturo Solis','999 410 0306'),
  ('CEI-0307','Rebeca Ku','999 410 0307'),
  ('CEI-0308','Ivan Pool','999 410 0308'),
  ('CEI-0309','Paola Canto','999 410 0309'),
  ('CEI-0310','Fernando Ek','999 410 0310')
)
insert into public.student_contacts (student_id, full_name, relationship, phone, primary_contact)
select student.id, data.tutor_name, 'Familiar', data.phone, true
from contact_data data
join public.students student on student.enrollment = data.enrollment
where not exists (
  select 1 from public.student_contacts contact
  where contact.student_id = student.id and contact.primary_contact
);
