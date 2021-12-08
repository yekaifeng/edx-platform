Terminology: CMS vs Studio
==========================

Synopsis
--------

There has been disagreement over whether Open edX's content authoring Web service is called "CMS" or "Studio".

This ADR decides that "CMS" is the name of the Web service. It powers the product called "Studio".

Status
------

Accepted


Context
-------

edx-platform contains two semi-coupled Django projects. Although the projects share a lot of code and data, they have two different Django entry points and are generally deployed as distinct Web services.

The Django project defined under the ``./lms`` directory has many responsibilities, but its cardinal role is to host the instructor- and learner-facing learning experience. The Web service deployed from it is consistently referred to as "LMS" (for Learning Management System).

The Django project defined under the ``./cms`` directory is responsible for authoring, versioning, and publishing learning content to LMS. The Web service deployed from it is interchangeably referred to as "CMS" (for Content Management System) and "Studio".

The primary user-facing Web application that CMS/Studio powers is named "Studio". Other applications include LabXChange, which uses the CMS/Studio's APIs to power its content authoring capabilities.

Let's choose one name for the Web service
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Having two names for the same thing is annoying, especially when that thing is a core component of a software ecosystem. Whenever a developer needs to reference CMS/Studio, either in code or in documentation, they must arbitrarily choose one name or the other. Often, they will have to justify why they chose one name over the other to reviewers, who may have mixed opinions on which name to use. This is a waste of time, and the end result is that our code is more confusing and less predictable.

Arguments in favor of "Studio"
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

* The environment variable used to specify CMS/Studio's configuration YAML path is ``STUDIO_CFG``.
* In both the old Ansible installation pathway and in Tutor, the default CMS/Studio domain is ``studio.<BASE_DOMAIN>``.
* Devstack calls the CMS/Studio docker-compose service ``studio``.
* It may be good for the Web service and the primary product it supports (Studio) to have the same name.
* Words (eg Studio) are more accessible to new community members than initialisms (eg CMS) are.

Arguments in favor of "CMS"
~~~~~~~~~~~~~~~~~~~~~~~~~~~

* The directory itself is named ``./cms``, and top-level code directories are hard to rename.
* All Django management commands against CMS/Studio are invoked as ``./manage.py cms ...``, which would also be hard to change.
* Tutor, the supported community installation, consistently calls the Web service "CMS" in its documentation and setting names.
* The old Ansible installation pathway (which is still in use at edX.org) consistently uses ``cms``.
* The CMS/Studio service supports at least one major product other than Studio: LabXChange. 
* Parts of the Studio interface are being reimplemented as micro-frontends, which are presented as being part of the "Studio" product but are hosted separately from the CMS/Studio Web service.

Decision
--------

We will call the Web service "CMS". Going forward, "Studio" should only be used to refer to the user-facing content authoring product powered by CMS.

We decide this because:

* The "Studio" code references are fairly easy to change; comparatively, the "CMS" code references are not.
* The disambiguation of the "Studio" as a product and "CMS" as a Web service allows each to evolve separately without generating future terminology confusion.


Consequences
------------

1. Immediately, the environment variable used to specify CMS/Studio's configuration YAML path will be changed to ``CMS_CFG``, allowing ``STUDIO_CFG`` to be used as a deprecated fallback. The ``STUDIO_CFG`` variable will be supported until at least the "O" named release.
2. Over time, references to "Studio" as a Web service, in devstack and elsewhere, will be changed to "CMS".
3. This ADR will hopefully be useful in any CMS vs. Studio terminology discussion going forward.
